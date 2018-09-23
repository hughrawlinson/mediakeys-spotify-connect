//
//  AppDelegate.swift
//  mediakeys-spotify-connect
//
//  Created by Hugh Rawlinson on 2017-05-20.
//  Copyright © 2017 Hugh Rawlinson. All rights reserved.
//

import AVFoundation
import Cocoa
import MediaPlayer

enum authError: Error {
    case failedLoadingRefreshTokenFromStore
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system().statusItem(withLength: -2)
    var accessToken: String? = nil
    
    var authServerURI: String? = nil
    var clientID: String? = nil
    var redirectURI: String? = nil

    func initiateSpotifyLogin(sender: AnyObject) {
        if (redirectURI != nil && clientID != nil && authServerURI != nil) {
            let urlEncodedRedirectUri = redirectURI!.encodeURIComponent()
            let authorizationUri = "\(authServerURI!)/login?scope=user-modify-playback-state+user-read-currently-playing&client_id=\(clientID!)&redirect_uri=\(urlEncodedRedirectUri)"
            if let url = URL(string: authorizationUri), NSWorkspace.shared().open(url) {}
        }
    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        let appleEventManager: NSAppleEventManager = NSAppleEventManager.shared()
        appleEventManager.setEventHandler(self, andSelector: #selector(handleGetURLEvent(event:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        if let path = Bundle.main.path(forResource: "Config", ofType: "plist"), let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject] {
            authServerURI = dict["authServerURI"] as? String
            clientID = dict["spotifyClientID"] as? String
            redirectURI = dict["redirectURI"] as? String
        }
    }
    
    func handleGetURLEvent(event: NSAppleEventDescriptor) {
        let url: String = event.paramDescriptor(forKeyword: keyDirectObject)!.stringValue!
        
        url.components(separatedBy: "#")[1].components(separatedBy: "&").forEach({ (keyValuePair) in
            ({keyValPair -> Void in
                if keyValPair[0] == "access_token" {
                    accessToken = keyValPair[1]
                    setUpPlaybackControlMenu()
                }
                if keyValPair[0] == "refresh_token" {
                    let dataDict: [String: String] = ["refreshToken": keyValPair[1]]
                    
                    let filePath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("mediakeys-spotify-connect", isDirectory: true)
                    if(!FileManager.default.fileExists(atPath: (filePath?.absoluteString)!)) {
                        do {
                            try FileManager.default.createDirectory(at: filePath!, withIntermediateDirectories: true, attributes: nil)
                        } catch {
                            return
                        }
                    }
                    
                    let refreshTokenStoreFilePath = filePath?.appendingPathComponent("refreshToken.plist")
                    
                    let data = NSKeyedArchiver.archivedData(withRootObject: dataDict)
                    do {
                        try data.write(to: refreshTokenStoreFilePath!)
                    } catch {
                        return
                    }
                }
            })(keyValuePair.components(separatedBy: "="))
        })
    }
    
    func next() {
        spotifyAPICall(httpMethod: "POST",
                       endpoint: "/v1/me/player/next",
                       handler: { (responseDict) in
                        print(responseDict)
                        
        })
    }
    
    func prev() {
        spotifyAPICall(httpMethod: "POST",
                       endpoint: "/v1/me/player/previous",
                       handler: { (responseDict) in
                        print(responseDict)
                        
        })
    }
    
    func togglePlayPause() {
        nowPlaying { (playing) in
            let action = playing as! Bool ? "pause" : "play"
            self.spotifyAPICall(httpMethod: "PUT",
                                endpoint: "/v1/me/player/\(action)",
                                handler: { (responseDict) in
                                 print(responseDict)
                            
            })
        }
    }
    
    func nowPlaying(handler: @escaping (Any) -> Void) {
        spotifyAPICall(httpMethod: "GET",
                       endpoint: "/v1/me/player/currently-playing",
                       handler: { (responseDict) in
                        guard let isPlaying = responseDict["is_playing"] else {
                            print("error")
                            return
                        }
                        handler(isPlaying)
                        
        })
    }
    
    func spotifyAPICall(httpMethod: String, endpoint: String, accessToken: String, handler: @escaping ([String: Any]) -> Void) {
        var request = URLRequest(url: URL(string: "https://api.spotify.com\(endpoint)")!)
        request.httpMethod = httpMethod
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("error=\(String(describing: error))")
                return
            }
            
            if let httpStatus = response as? HTTPURLResponse, httpStatus.statusCode < 200, httpStatus.statusCode >= 300 {
                print("statusCode should be 200, but is \(httpStatus.statusCode)")
                print("response = \(String(describing: response))")
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data, options: []) else {
                return
            }
            
            guard let dictionary = json as? [String: Any] else {
                return
            }
            
            handler(dictionary)
        }
        task.resume()
    }
    
    func spotifyAPICall(httpMethod: String, endpoint: String, handler: @escaping ([String: Any]) -> Void) {
        guard (accessToken != nil) else {
            print("Access Token is Nil")
            return
        }
        
        spotifyAPICall(httpMethod: httpMethod, endpoint: endpoint, accessToken: accessToken!, handler: handler)
    }
    
    func setUpLoginMenu() {
        if let button = statusItem.button {
            button.image = NSImage(named: "StatusBarButtonImage")
            
            let menu = NSMenu()
            
            menu.addItem(NSMenuItem(title: "Connect your Spotify Account", action: #selector(initiateSpotifyLogin(sender:)), keyEquivalent: "P"))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.shared().terminate), keyEquivalent: "q"))
            
            statusItem.menu = menu
        }
    }
    
    func setUpPlaybackControlMenu() {
        if let button = statusItem.button {
            button.image = NSImage(named: "StatusBarButtonImage")
            
            let menu = NSMenu()
            
            menu.addItem(NSMenuItem(title: "Toggle Play/Pause", action: #selector(togglePlayPause), keyEquivalent: "J"))
            menu.addItem(NSMenuItem(title: "Skip Previous", action: #selector(prev), keyEquivalent: "H"))
            menu.addItem(NSMenuItem(title: "Skip Next", action: #selector(next), keyEquivalent: "L"))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.shared().terminate), keyEquivalent: "q"))
            
            statusItem.menu = menu
        }
    }
    
    func accessTokenFromRefreshToken(refreshToken: String, handler: @escaping (_: String) -> Void) throws {
        var request = URLRequest(url: URL(string: "\(authServerURI!)/refresh?clientId=\(clientID!)&refreshToken=\(refreshToken)")!)
        request.httpMethod = "GET"
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("error=\(String(describing: error))")
                return
            }
            
            if let httpStatus = response as? HTTPURLResponse, httpStatus.statusCode < 200, httpStatus.statusCode >= 300 {
                print("statusCode should be 200, but is \(httpStatus.statusCode)")
                print("response = \(String(describing: response))")
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data, options: []) else {
                return
            }
            
            guard let dictionary = json as? [String: Any] else {
                return
            }
            
            handler(dictionary["access_token"] as! String)
        }
        task.resume()
    }
    
    func getAccessTokenFromStoredRefreshToken(handler: @escaping (_: String) -> Void) throws {
        let fullPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("mediakeys-spotify-connect", isDirectory: true).appendingPathComponent("refreshToken.plist")
        print((fullPath?.absoluteString)!)
        
        // TODO: Looks like it gets rekt here
        //guard let loadedStrings = NSKeyedUnarchiver.unarchiveObject(withFile: (fullPath?.absoluteString)!) as? [String: String] else {
        guard let loadedStrings = NSKeyedUnarchiver.unarchiveObject(withFile: (fullPath?.absoluteString)!) else {
            throw authError.failedLoadingRefreshTokenFromStore
        }
        print(loadedStrings)
        // try accessTokenFromRefreshToken(refreshToken: loadedStrings["refreshToken"]!, handler: handler)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        do {
            try getAccessTokenFromStoredRefreshToken(handler: { (newAccessToken) in
                print(newAccessToken)
                self.accessToken = newAccessToken
                self.setUpPlaybackControlMenu()
            })
        } catch {
            setUpLoginMenu()
        }
        
        MPRemoteCommandCenter.shared().playCommand.addTarget { (commandEvent) -> MPRemoteCommandHandlerStatus in
            NSLog("Playing")
            self.togglePlayPause()
            return MPRemoteCommandHandlerStatus.success
        }
        
        MPRemoteCommandCenter.shared().pauseCommand.addTarget { (commandEvent) -> MPRemoteCommandHandlerStatus in
            NSLog("Pausing")
            self.togglePlayPause()
            return MPRemoteCommandHandlerStatus.success
        }
        
        MPRemoteCommandCenter.shared().togglePlayPauseCommand.addTarget { (commandEvent) -> MPRemoteCommandHandlerStatus in
            NSLog("Toggling")
            self.togglePlayPause()
            return MPRemoteCommandHandlerStatus.success
        }
        
        MPRemoteCommandCenter.shared().skipForwardCommand.addTarget { (commandEvent) -> MPRemoteCommandHandlerStatus in
            NSLog("Skip Forward")
            self.next()
            return MPRemoteCommandHandlerStatus.success
        }
        
        MPRemoteCommandCenter.shared().skipBackwardCommand.addTarget { (commandEvent) -> MPRemoteCommandHandlerStatus in
            NSLog("Skip Backward")
            self.prev()
            return MPRemoteCommandHandlerStatus.success
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
}

extension String {
    func encodeURIComponent() -> String {
        let characterSet = NSMutableCharacterSet.alphanumeric()
        characterSet.addCharacters(in: "-_.!~*'()")
        return self.addingPercentEncoding(withAllowedCharacters: characterSet as CharacterSet)!
    }
}



