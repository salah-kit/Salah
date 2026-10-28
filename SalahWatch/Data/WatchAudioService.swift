import AVFoundation
import Foundation
import Observation

/// Plays a prayer's sound while Salah is open on the watch: the bundled adhan, the soft tone,
/// and the optional du'a after an adhan, through the watch's speaker or its headphones.
/// Nothing plays once Salah leaves the screen.
@MainActor @Observable
final class WatchAudioService: NSObject, AVAudioPlayerDelegate,
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
  @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

  init(files: IOSAudioFiles = IOSAudioFiles()) {
    self.files = files
    super.init()
    speech.delegate = self
    interruptionObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.stop() }
    }
  }

  isolated deinit {
    duaTimeoutTask?.cancel()
    if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
  }

  /// The sounds the watch plays: the bundled recordings and the tone. A system sound or an
  /// imported recording chosen on the iPhone plays the tone, as neither is on the watch.
  nonisolated static func playable(_ sound: IOSSound) -> IOSSound {
    switch sound {
    case .adhan, .fajrAdhan, .none: sound
    case .softTone, .system, .custom: .softTone
    }
  }

  /// Plays `sound` at `volume` (0–1). A du'a follows an adhan when asked. Returns whether
  /// anything started.
  @discardableResult
  func play(_ sound: IOSSound, volume: Double, duaAfter: Bool = false) -> Bool {
    stop()
    errorMessage = nil
    self.volume = min(1, max(0, volume.isFinite ? volume : 0.75))
    let sound = Self.playable(sound)
    if sound == .softTone { try? files.prepareSoftTone() }
    guard sound != .none else { return false }
    guard let url = files.playbackURL(for: sound) else {
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
      hasQueuedDua =
        duaAfter && sound != .softTone && AVSpeechSynthesisVoice(language: "ar-SA") != nil
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

  /// The du'a after the adhan, as the iPhone app speaks it.
  nonisolated static let dua =
    "اللَّهُمَّ رَبَّ هَذِهِ الدَّعْوَةِ التَّامَّةِ وَالصَّلَاةِ الْقَائِمَةِ آتِ مُحَمَّدًا الْوَسِيلَةَ وَالْفَضِيلَةَ وَابْعَثْهُ مَقَامًا مَحْمُودًا الَّذِي وَعَدْتَهُ"
}
