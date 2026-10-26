import AVFoundation
import Foundation
import MediaPlayer
import Observation

/// Plays a prayer's sound while Salah is open: the bundled adhan, the soft tone, and the
/// optional du'a after an adhan. Nothing plays once Salah leaves the screen.
@MainActor @Observable
final class TVAudioService: NSObject, AVAudioPlayerDelegate,
  @preconcurrency AVSpeechSynthesizerDelegate
{
  private(set) var isPlaying = false
  private(set) var isPlayingDua = false
  private(set) var hasQueuedDua = false
  private(set) var errorMessage: String?
  @ObservationIgnored var onPlaybackChanged: ((Bool) -> Void)?

  @ObservationIgnored private let files: IOSAudioFiles
  @ObservationIgnored private var player: AVAudioPlayer?
  @ObservationIgnored private let speech = AVSpeechSynthesizer()
  @ObservationIgnored private var activeUtterance: AVSpeechUtterance?
  @ObservationIgnored private var duaTimeoutTask: Task<Void, Never>?
  @ObservationIgnored private var volume = 0.75
  @ObservationIgnored private var playbackLocale = Locale.current
  @ObservationIgnored private var commandTargets: [(MPRemoteCommand, Any)] = []
  @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

  /// tvOS keeps only its defaults across launches, so the generated tone lives in the
  /// caches, where it is made again whenever the system clears them.
  init(files: IOSAudioFiles = TVAudioService.cachedFiles) {
    self.files = files
    super.init()
    speech.delegate = self
    interruptionObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.stop() }
    }
    let commands = MPRemoteCommandCenter.shared()
    for command in [commands.stopCommand, commands.pauseCommand, commands.togglePlayPauseCommand] {
      command.isEnabled = true
      let target = command.addTarget { [weak self] _ in
        Task { @MainActor in self?.stop() }
        return .success
      }
      commandTargets.append((command, target))
    }
  }

  isolated deinit {
    duaTimeoutTask?.cancel()
    if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    for (command, target) in commandTargets { command.removeTarget(target) }
  }

  nonisolated static var cachedFiles: IOSAudioFiles {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Audio", isDirectory: true)
    return IOSAudioFiles(
      audioDirectory: caches, soundsDirectory: caches,
      resourcesDirectory: AppResources.bundle.resourceURL)
  }

  /// The sounds an Apple TV can play: no system sound, and no imported recordings.
  nonisolated static let sounds: [IOSSound] = [.fajrAdhan, .adhan, .softTone, .none]

  /// Plays `sound` at `volume` (0–1). A du'a follows an adhan when asked. Returns whether
  /// anything started.
  @discardableResult
  func play(_ sound: IOSSound, volume: Double, duaAfter: Bool = false, locale: Locale) -> Bool {
    stop()
    errorMessage = nil
    self.volume = min(1, max(0, volume.isFinite ? volume : 0.75))
    playbackLocale = locale
    let url: URL?
    switch sound {
    case .adhan, .fajrAdhan:
      url = files.playbackURL(for: sound)
    case .softTone, .system, .custom:
      // An Apple TV has no system sounds or imported recordings; the tone stands in.
      try? files.prepareSoftTone()
      url = files.playbackURL(for: .softTone)
    case .none:
      return false
    }
    guard let url else {
      errorMessage = "This sound couldn’t be found."
      return false
    }
    do {
      let player = try AVAudioPlayer(contentsOf: url)
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default)
      try session.setActive(true)
      player.delegate = self
      player.volume = Float(self.volume)
      player.prepareToPlay()
      guard player.play() else { throw IOSAudioImportError.unreadable }
      self.player = player
      switch sound {
      case .adhan, .fajrAdhan:
        hasQueuedDua = duaAfter && AVSpeechSynthesisVoice(language: "ar-SA") != nil
      default:
        hasQueuedDua = false
      }
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlaying(
        isDua: false, duration: player.duration)
      updatePlaying(true)
      return true
    } catch {
      stop()
      errorMessage = "This sound couldn’t be played."
      return false
    }
  }

  func setVolume(_ value: Double) {
    volume = min(1, max(0, value.isFinite ? value : 0.75))
    player?.volume = Float(volume)
  }

  func stop() {
    hasQueuedDua = false
    duaTimeoutTask?.cancel()
    duaTimeoutTask = nil
    player?.delegate = nil
    player?.stop()
    player = nil
    activeUtterance = nil
    if speech.isSpeaking { speech.stopSpeaking(at: .immediate) }
    isPlayingDua = false
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    updatePlaying(false)
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    guard self.player === player else { return }
    self.player?.delegate = nil
    self.player = nil
    guard flag, hasQueuedDua, let voice = AVSpeechSynthesisVoice(language: "ar-SA") else {
      stop()
      return
    }
    hasQueuedDua = false
    isPlayingDua = true
    duaTimeoutTask = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(IOSPlaybackSession.duaMaximumDuration)) } catch {
        return
      }
      guard let self, self.isPlayingDua else { return }
      self.stop()
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlaying(isDua: true, duration: nil)
    let utterance = AVSpeechUtterance(string: Self.dua)
    utterance.voice = voice
    utterance.volume = Float(volume)
    utterance.rate = 0.42
    activeUtterance = utterance
    speech.speak(utterance)
    onPlaybackChanged?(true)
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
    guard self.player === player else { return }
    stop()
    errorMessage = "This sound couldn’t be played."
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance)
  {
    guard player == nil, activeUtterance === utterance else { return }
    stop()
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance)
  {
    guard player == nil, isPlaying, activeUtterance === utterance else { return }
    stop()
  }

  private func updatePlaying(_ value: Bool) {
    guard isPlaying != value else { return }
    isPlaying = value
    onPlaybackChanged?(value)
  }

  private func nowPlaying(isDua: Bool, duration: TimeInterval?) -> [String: Any] {
    let copy = TVCopy(locale: playbackLocale)
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: isDua
        ? copy("Du’a after adhan", "الدعاء بعد الأذان") : copy("Adhan", "الأذان"),
      MPMediaItemPropertyArtist: copy("Salah", "صلاة"),
      MPNowPlayingInfoPropertyElapsedPlaybackTime: 0,
      MPNowPlayingInfoPropertyPlaybackRate: 1,
    ]
    if let duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
    return info
  }

  /// The du'a after the adhan, as the iPhone app speaks it.
  nonisolated static let dua =
    "اللَّهُمَّ رَبَّ هَذِهِ الدَّعْوَةِ التَّامَّةِ وَالصَّلَاةِ الْقَائِمَةِ آتِ مُحَمَّدًا الْوَسِيلَةَ وَالْفَضِيلَةَ وَابْعَثْهُ مَقَامًا مَحْمُودًا الَّذِي وَعَدْتَهُ"
}
