//
//  SBDatabaseController+Progress.swift
//  Submariner
//
//  Created by Rafaël Warnault on 04/06/11.
//  Copyright (c) 2011-2014, Rafaël Warnault. All rights reserved.
//

import Cocoa

extension SBDatabaseController {
    @objc func clearPlaybackProgress() {
        progressSlider.isEnabled = false
        progressTextField.stringValue = "00:00"
        durationTextField.stringValue = "-00:00"
        progressSlider.doubleValue = 0
    }

    @objc func installProgressTimer() {
        if progressUpdateTimer != nil {
            return
        }
        progressUpdateTimer = Timer.scheduledTimer(timeInterval: 0.1,
                                                   target: self,
                                                   selector: #selector(updateProgress(_:)),
                                                   userInfo: nil,
                                                   repeats: true)
    }

    @objc func uninstallProgressTimer() {
        if let timer = progressUpdateTimer {
            timer.invalidate()
            progressUpdateTimer = nil
        }
    }

    @objc func updateProgress() {
        progressSlider.isEnabled = true
        let player = SBPlayer.sharedInstance()
        let currentTimeString = player.currentTimeString
        let remainingTimeString = player.remainingTimeString
        let progress = player.progress
        
        progressTextField.stringValue = currentTimeString
        durationTextField.stringValue = remainingTimeString
        if progress > 0 {
            progressSlider.doubleValue = progress
        }
    }

    @objc func updateProgress(_ timer: Timer) {
        let player = SBPlayer.sharedInstance()
        if player.isPlaying {
            if player.isPaused {
                return
            }
            
            let visible = self.window?.occlusionState.contains(.visible) == true
            if !visible {
                return
            }
            
            self.updateProgress()
        } else {
            self.clearPlaybackProgress()
        }
    }
}
