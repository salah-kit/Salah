import AVFoundation
import AudioToolbox
import Foundation
import MediaPlayer
import Observation
import UIKit

/// Full playback starts only from an explicit action; previews stop on backgrounding.
@MainActor @Observable
final class IOSAudioService: NSObject, AVAudioPlayerDelegate,
  @preconcurrency AVSpeechSynthesizerDelegate
{
  private(set) var isPlaying = false
  private(set) var isPlayingDua = false
  private(set) var hasQueuedDua = false
  private(set) var currentSound: IOSSound?
  private(set) var playbackStartedAt: Date?
  private(set) var expectedPlaybackEnd: Date?
  private(set) var errorMessage: String?
  var onPlaybackChanged: ((Bool) -> Void)?

  @ObservationIgnored private let files: IOSAudioFiles
  @ObservationIgnored private var player: AVAudioPlayer?
  @ObservationIgnored private let speech = AVSpeechSynthesizer()
  @ObservationIgnored private var activeUtterance: AVSpeechUtterance?
  @ObservationIgnored private var duaTimeoutTask: Task<Void, Never>?
  @ObservationIgnored private var volume = 1.0
  @ObservationIgnored private var playbackLocale = Locale.current
  @ObservationIgnored private var isPreview = false
  @ObservationIgnored private var observers: [NSObjectProtocol] = []
  @ObservationIgnored private var commandTargets: [(MPRemoteCommand, Any)] = []

  init(files: IOSAudioFiles = IOSAudioFiles()) {
    self.files = files
    super.init()
    speech.delegate = self
    do { try files.prepareSounds() } catch {
      errorMessage = "Sound files could not be prepared. Try reopening Salah."
    }
    observers.append(
      NotificationCenter.default.addObserver(
        forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in if self?.isPreview == true { self?.stop() } }
      })
    for name in [AVAudioSession.interruptionNotification] {
      observers.append(
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
          [weak self] _ in
          Task { @MainActor in self?.stop() }
        })
    }
    observers.append(
      NotificationCenter.default.addObserver(
        forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
      ) { [weak self] notification in
        let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else {
          return
        }
        Task { @MainActor in self?.stop() }
      })
    let commands = MPRemoteCommandCenter.shared()
    for command in [commands.stopCommand, commands.pauseCommand] {
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
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    for (command, target) in commandTargets { command.removeTarget(target) }
  }

  func importAudio(from url: URL) async throws -> IOSSound {
    let files = files
    do {
      let filename = try await Task.detached(priority: .userInitiated) {
        try files.importAudio(from: url)
      }.value
      return .custom(filename)
    } catch let error as IOSAudioImportError {
      throw error
    } catch {
      throw IOSAudioImportError.unreadable
    }
  }

  func preview(_ sound: IOSSound, volume: Double) {
    play(sound, volume: volume)
    isPreview = true
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }

  func play(
    _ sound: IOSSound, volume: Double, duaAfter: Bool = false,
    locale: Locale = .current
  ) {
    stop()
    errorMessage = nil
    self.volume = Self.clampedVolume(volume)
    playbackLocale = locale
    isPreview = false
    let queueDua: Bool
    switch sound {
    case .adhan, .fajrAdhan, .custom: queueDua = duaAfter
    default: queueDua = false
    }
    if sound == .none { return }
    if sound == .system {
      AudioServicesPlaySystemSound(1007)
      // A system preview is short and has no controllable playback session or du'a.
      return
    }
    start(sound, queueDua: queueDua)
  }

  func setVolume(_ value: Double) {
    volume = Self.clampedVolume(value)
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
    speech.stopSpeaking(at: .immediate)
    currentSound = nil
    isPlayingDua = false
    playbackStartedAt = nil
    expectedPlaybackEnd = nil
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    updatePlayback(false)
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func start(_ sound: IOSSound, queueDua: Bool) {
    do {
      guard let url = files.playbackURL(for: sound) else { throw IOSAudioImportError.unreadable }
      let player = try AVAudioPlayer(contentsOf: url)
      let duration = try IOSAudioDurationPolicy.sessionDuration(
        recordingDuration: player.duration, hasQueuedDua: queueDua)
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default)
      try session.setActive(true)
      player.delegate = self
      player.volume = Float(volume)
      player.prepareToPlay()
      self.player = player
      guard player.play() else { throw IOSAudioImportError.unreadable }
      hasQueuedDua = queueDua
      currentSound = sound
      let startedAt = Date()
      playbackStartedAt = startedAt
      expectedPlaybackEnd = startedAt.addingTimeInterval(duration)
      if !isPreview {
        let labels = IOSAudioMetadata(locale: playbackLocale, isDua: false)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
          MPMediaItemPropertyTitle: labels.title,
          MPMediaItemPropertyArtist: labels.artist,
          MPMediaItemPropertyPlaybackDuration: player.duration,
          MPNowPlayingInfoPropertyElapsedPlaybackTime: 0,
          MPNowPlayingInfoPropertyPlaybackRate: 1,
        ]
      }
      updatePlayback(true)
    } catch let error as IOSAudioImportError {
      stop()
      errorMessage = error.errorDescription
    } catch {
      stop()
      errorMessage = "This audio could not be played."
    }
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    guard self.player === player else { return }
    self.player?.delegate = nil
    self.player = nil
    guard flag else {
      stop()
      return
    }
    if hasQueuedDua {
      hasQueuedDua = false
      isPlayingDua = true
      let now = Date()
      let latestEnd = (playbackStartedAt ?? now).addingTimeInterval(
        IOSPlaybackSession.maximumDuration)
      let end = min(now.addingTimeInterval(IOSPlaybackSession.duaMaximumDuration), latestEnd)
      expectedPlaybackEnd = end
      duaTimeoutTask = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow))) } catch {
          return
        }
        guard let self, self.isPlayingDua else { return }
        self.stop()
      }
      if !isPreview {
        let labels = IOSAudioMetadata(locale: playbackLocale, isDua: true)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
          MPMediaItemPropertyTitle: labels.title,
          MPMediaItemPropertyArtist: labels.artist,
          MPNowPlayingInfoPropertyElapsedPlaybackTime: 0,
          MPNowPlayingInfoPropertyPlaybackRate: 1,
        ]
      }
      let utterance = AVSpeechUtterance(
        string:
          "اللَّهُمَّ رَبَّ هَذِهِ الدَّعْوَةِ التَّامَّةِ وَالصَّلَاةِ الْقَائِمَةِ آتِ مُحَمَّدًا الْوَسِيلَةَ وَالْفَضِيلَةَ وَابْعَثْهُ مَقَامًا مَحْمُودًا الَّذِي وَعَدْتَهُ"
      )
      utterance.voice = AVSpeechSynthesisVoice(language: "ar-SA")
      utterance.volume = Float(volume)
      utterance.rate = 0.42
      activeUtterance = utterance
      speech.speak(utterance)
      onPlaybackChanged?(true)
    } else {
      stop()
    }
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
    guard self.player === player else { return }
    stop()
    errorMessage = "This audio could not be played."
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance)
  {
    guard player == nil, activeUtterance === utterance else { return }
    stop()
  }

  private func updatePlayback(_ value: Bool) {
    guard isPlaying != value else { return }
    isPlaying = value
    onPlaybackChanged?(value)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance)
  {
    guard player == nil, isPlaying, activeUtterance === utterance else { return }
    stop()
  }

  nonisolated static func clampedVolume(_ value: Double) -> Double {
    value.isFinite ? max(0, min(1, value)) : 1
  }
}

/// Selected-language metadata is shared by the adhan and its following du'a phase.
nonisolated struct IOSAudioMetadata: Equatable, Sendable {
  let title: String
  let artist: String

  init(locale: Locale, isDua: Bool) {
    title =
      isDua
      ? IOSL10n.text("Du’a after adhan", arabic: "الدعاء بعد الأذان", locale: locale)
      : IOSL10n.text("Adhan", arabic: "الأذان", locale: locale)
    artist = IOSL10n.text("Salah", arabic: "صلاة", locale: locale)
  }
}
