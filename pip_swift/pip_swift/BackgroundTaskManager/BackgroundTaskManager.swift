//
//  BackgroundTaskManager.swift
//  pip_swift
//
//  Created by 无夜之星辰 on 2022/8/31.
//

import Foundation
import AVFAudio
import AVKit

class BackgroundTaskManager: NSObject, AVAudioPlayerDelegate {
    
    static let shared = BackgroundTaskManager()
    
    func startPlay() {
        guard let audioPlayer else {
            AppDebugLogger.logCritical("静音音频保活启动失败：播放器不存在")
            return
        }
        guard !isKeepAliveAudioActive else {
            if !audioPlayer.isPlaying {
                let resumed = audioPlayer.play()
                isKeepAliveAudioActive = resumed && audioPlayer.isPlaying
                AppDebugLogger.logCritical("静音音频保活恢复：success=\(resumed)，\(diagnosticsText)")
            }
            return
        }
        guard configureAudioSession() else { return }
        audioPlayer.prepareToPlay()
        let started = audioPlayer.play()
        isKeepAliveAudioActive = audioPlayer.isPlaying
        AppDebugLogger.logCritical("静音音频保活启动：success=\(started)，\(diagnosticsText)")
    }
    
    func stopPlay() {
        guard isKeepAliveAudioActive || audioPlayer?.isPlaying == true else { return }
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isKeepAliveAudioActive = false
        deactivateAudioSession()
        AppDebugLogger.logCritical("静音音频保活停止：\(diagnosticsText)")
    }

    func forceStopAndDeactivate() {
        guard isKeepAliveAudioActive || audioPlayer?.isPlaying == true else { return }
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isKeepAliveAudioActive = false
        deactivateAudioSession()
    }

    var isPlaying: Bool {
        isKeepAliveAudioActive && audioPlayer?.isPlaying == true
    }

    var diagnosticsText: String {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ",")
        return [
            "playing=\(audioPlayer?.isPlaying ?? false)",
            "activeFlag=\(isKeepAliveAudioActive)",
            "time=\(String(format: "%.2f", audioPlayer?.currentTime ?? 0))",
            "category=\(session.category.rawValue)",
            "mode=\(session.mode.rawValue)",
            "otherAudio=\(session.isOtherAudioPlaying)",
            "route=\(outputs.isEmpty ? "none" : outputs)"
        ].joined(separator: ",")
    }
    
    private var audioPlayer: AVAudioPlayer?
    private var isKeepAliveAudioActive = false
    
    private override init() {
        super.init()
        guard let mp3URL = Bundle.main.url(forResource: "slience", withExtension: "mp3") else {
            print("未找到静音音频")
            return
        }

        do {
            try audioPlayer = AVAudioPlayer(contentsOf: mp3URL)
            audioPlayer?.volume = 0
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
        } catch {
            AppDebugLogger.logCritical("静音音频初始化失败：\(error.localizedDescription)")
        }
    }

    @discardableResult
    private func configureAudioSession() -> Bool {
        do {
            // 设置后台模式和锁屏模式下依旧能够播放
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            return true
        } catch {
            AppDebugLogger.logCritical("静音音频会话启动失败：\(error.localizedDescription)，\(diagnosticsText)")
            return false
        }
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            AppDebugLogger.logCritical("静音音频会话停用失败：\(error.localizedDescription)，\(diagnosticsText)")
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        isKeepAliveAudioActive = false
        AppDebugLogger.logCritical("静音音频解码失败：\(error?.localizedDescription ?? "未知错误")，\(diagnosticsText)")
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isKeepAliveAudioActive = false
        AppDebugLogger.logCritical("静音音频意外结束：success=\(flag)，\(diagnosticsText)")
    }
    
}
