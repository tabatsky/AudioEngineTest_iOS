//
//  ContentView.swift
//  SoxTest_iOS
//
//  Created by User on 09.05.2024.
//

import SwiftUI
import MediaPlayer
import StoreKit
import AVFoundation

struct ContentView: View {
    
    @State var mediaItems: [MPMediaItem]? = nil
    
    @State private var tempo: Float = 1.0

    let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
    
    var body: some View {
        let _ = listMusic()
        
        VStack {
            HStack {
                Button(action: {
                    AudioManager.shared.pauseAudio()
                }, label: {
                    Text("Pause")
                })
                TextField("Tempo", value: $tempo, formatter: formatter)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                    .frame(width: 120.0)
                Button(action: {
                    AudioManager.shared.applyTempo(tempo)
                }, label: {
                    Text("Apply Tempo")
                })
            }
            .frame(height: 80.0)
            if let mediaItems = mediaItems?.sorted(by: { item1, item2 in
                item1.artistWithTitle < item2.artistWithTitle
            }) {
                ScrollView {
                    LazyVStack {
                        ForEach(mediaItems.indices) { index in
                            let item = mediaItems[index]
                            Button(action: {
                                if let url = item.assetURL {
                                    Task.detached(operation: {
                                        await AudioManager.shared.startAudio(url: url)
                                    })
                                }
                            }, label: {
                                Text(item.artistWithTitle)
                            })
                            .frame(height: 30.0)
                        }
                    }
                }
            }
        }
        .padding()
    }
    
    func listMusic() {
        SKCloudServiceController.requestAuthorization {(status: SKCloudServiceAuthorizationStatus) in
            switch status {
            case .denied, .restricted: onDisabled()
            case .authorized: onEnabled()
            default: break
            }
        }
    }
    
    func onDisabled() {}
    
    func onEnabled() {
        mediaItems = MPMediaQuery.songs().items
    }
}

#Preview {
    ContentView()
}

final class AudioManager {
    static let shared = AudioManager()

    private let player = AVAudioPlayerNode()
    private let speedControl = AVAudioUnitVarispeed()
    private let pitchControl = AVAudioUnitTimePitch()
    
    private let engine = AVAudioEngine()

    private var session = AVAudioSession.sharedInstance()

    private init() {}
    
    private func activateSession() {
        do {
            try session.setCategory(
                .playback,
                mode: .default,
                options: []
            )
        } catch _ {}
        
        do {
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch _ {}
        
        do {
            try session.overrideOutputAudioPort(.speaker)
        } catch _ {}
    }
    
    func startAudio(url: URL) async {
            
        // activate our session before playing audio
        //activateSession()
        
        // TODO: change the url to whatever audio you want to play
        let asset = try! AVURLAsset(url: url)
        
        let dir = try! FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first,
            create: true
        )
                 
        let outputURL = dir
            .appending(component: "file")
            .appendingPathExtension("m4a")
        try! await export(asset: asset, outputURL: outputURL)
        print(outputURL)
        
        let file = try! AVAudioFile(forReading: outputURL)
        
        engine.attach(player)
        engine.attach(pitchControl)
        engine.attach(speedControl)

        engine.connect(player, to: speedControl, format: nil)
        engine.connect(speedControl, to: pitchControl, format: nil)
        engine.connect(pitchControl, to: engine.mainMixerNode, format: nil)
        
//        engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
        
        player.scheduleFile(file, at: nil, completionHandler: nil)
        
        try! engine.start()
        
        player.play()
    }
    
    func applyTempo(_ tempo: Float) {
        let log2tempo = log2(tempo)
        let deltaPitch = -1200 * log2tempo
        pitchControl.pitch = deltaPitch
        speedControl.rate = tempo
    }

    func pauseAudio() {
        player.pause()
    }
    
    private func export(
            asset: AVAsset,
            outputURL: URL
        ) async throws {
            guard let exportSession = AVAssetExportSession(
                asset: asset,
                presetName: AVAssetExportPresetAppleM4A
            ) else {
                print("fuck")
                return
            }
            exportSession.outputURL = outputURL
            exportSession.outputFileType = AVFileType.m4a
            await exportSession.export()
        }
}
 
extension MPMediaItem {
    var artistWithTitle: String {
        let artist = self.artist ?? "";
        let title = self.title ?? "";
        return "\(artist) - \(title)"
    }
}
