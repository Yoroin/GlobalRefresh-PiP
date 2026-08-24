//
//  BackgroundTaskManager.swift
//  pip_swift
//
//  Created by 无夜之星辰 on 2022/8/31.
//

import Foundation
import AVFAudio
import AVKit

class BackgroundTaskManager: NSObject {
    
    static let shared = BackgroundTaskManager()
    
    func startPlay() {
        guard let audioPlayer else { return }
        guard !isKeepAliveAudioActive else {
            if !audioPlayer.isPlaying {
                audioPlayer.play()
            }
            return
        }
        configureAudioSession()
        audioPlayer.prepareToPlay()
        audioPlayer.play()
        isKeepAliveAudioActive = audioPlayer.isPlaying
    }
    
    func stopPlay() {
        guard isKeepAliveAudioActive || audioPlayer?.isPlaying == true else { return }
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isKeepAliveAudioActive = false
        deactivateAudioSession()
    }

    func forceStopAndDeactivate() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isKeepAliveAudioActive = false
        deactivateAudioSession()
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
            audioPlayer?.prepareToPlay()
        } catch {
            print(error)
        }
    }

    private func configureAudioSession() {
        do {
            // 设置后台模式和锁屏模式下依旧能够播放
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print(error)
        }
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print(error)
        }
    }
    
}
