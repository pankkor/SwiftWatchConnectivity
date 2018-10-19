//
//  SwiftWatchConnectivity.swift
//
//  Created by Matsuo Keisuke on 10/9/17.
//  Copyright © 2017 Keisuke Matsuo. All rights reserved.
//

import Foundation
import WatchKit
import WatchConnectivity

public protocol SwiftWatchConnectivityDelegate: NSObjectProtocol {
    func connectivity(_ swiftWatchConnectivity: SwiftWatchConnectivity, updatedWithTask task: SwiftWatchConnectivity.Task)
}

public class SwiftWatchConnectivity: NSObject {

    public enum Task {
        case updateApplicationContext([String: Any])
        case transferUserInfo([String: Any])
        case transferFile(URL, [String: Any]?)
        case sendMessage([String: Any])
        case sendMessageData(Data)
    }

    /// MARK: Type Properties
    public static let shared = SwiftWatchConnectivity()

    /// MARK: Public Properties
    public weak var delegate: SwiftWatchConnectivityDelegate? {
        didSet {
            invoke()
            invokeReceivedTasks()
        }
    }

    /// MARK: Private Properties
    fileprivate var tasks: [Task] = []
    fileprivate var latestApplicationContext: [String: Any]? // the latest application context

    fileprivate var receivedTasks: [Task] = []
    fileprivate var activationState: WCSessionActivationState = .notActivated
    #if os(watchOS)
    fileprivate var backgroundTasks: [WKRefreshBackgroundTask] = []
    #endif

    /**
     check all conditions
     */
    fileprivate var isAvailableMessage: Bool {
        guard WCSession.default.isReachable else { return false }
        guard activationState == .activated else { return false }
        return true
    }

    fileprivate var isAvailableApplicationContext: Bool {
        guard WCSession.default.isReachable else { return false }
        guard activationState == .activated else { return false }
        return true
    }

    fileprivate var isAvailableTransferUserInfo: Bool {
        guard WCSession.default.isReachable else { return false }
        guard activationState == .activated else { return false }
        return true
    }

    /// MARK: Initializations
    public override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// MARK: Type Methods
    /// MARK: Public Methods

    /// If onlyLatest is true then task is not added to the queue.
    /// Useful when only the latest applicationContext matters
    public func updateApplicationContext(context: [String: Any], onlyLatest: Bool = false) {
        if onlyLatest {
            latestApplicationContext = context
        } else {
            tasks.append(.updateApplicationContext(context))
        }
        invoke()
    }

    public func transferUserInfo(userInfo: [String: Any]) {
        tasks.append(.transferUserInfo(userInfo))
        invoke()
    }

    public func transferFile(fileURL: URL, metadata: [String: Any]) {
        tasks.append(.transferFile(fileURL, metadata))
        invoke()
    }

    public func sendMesssage(message: [String: Any]) {
        tasks.append(.sendMessage(message))
        invoke()
    }

    public func sendMesssageData(data: Data) {
        tasks.append(.sendMessageData(data))
        invoke()
    }

    /// MARK: Private Methods
    private func invoke() {
        guard activationState == .activated else { return }
        guard delegate != nil else { return }

        var remainTasks: [Task] = []
        for task in tasks {
            switch task {
            case .updateApplicationContext(let context):
                guard isAvailableApplicationContext && invokeUpdateApplicationContext(context) else {
                    remainTasks.append(task)
                    continue
                }
            case .transferUserInfo(let userInfo):
                guard isAvailableTransferUserInfo else {
                    remainTasks.append(task)
                    continue
                }
                invokeTransferUserInfo(userInfo)
            case .transferFile(let fileURL, let medatada):
                guard isAvailableTransferUserInfo else {
                    remainTasks.append(task)
                    continue
                }
                invokeTransferFile(fileURL, medatada: medatada)
            case .sendMessage(let message):
                guard isAvailableMessage else {
                    remainTasks.append(task)
                    continue
                }
                invokeSendMessage(message)
            case .sendMessageData(let data):
                guard isAvailableMessage else {
                    remainTasks.append(task)
                    continue
                }
                invokeSendMessageData(data)
            }
        }

        tasks.removeAll()
        tasks.append(contentsOf: remainTasks)

        // invoke latest application context
        if let latestApplicationContext = latestApplicationContext, isAvailableApplicationContext && invokeUpdateApplicationContext(latestApplicationContext) {
            self.latestApplicationContext = nil
        }
    }

    private func invokeUpdateApplicationContext(_ context: [String: Any]) -> Bool {
        do {
            try WCSession.default.updateApplicationContext(context)
            return true
        } catch {
            print("updateApplicationContext error: \(error)")
            return false
        }
    }

    private func invokeTransferUserInfo(_ userInfo: [String: Any]) {
        WCSession.default.transferUserInfo(userInfo)
    }

    private func invokeTransferFile(_ fileURL: URL, medatada: [String: Any]?) {
        WCSession.default.transferFile(fileURL, metadata: medatada)
    }

    private func invokeSendMessage(_ message: [String: Any]) {
        WCSession.default.sendMessage(message, replyHandler: { (reply) in
            print("reply: \(reply)")
        }) { (error) in
            print("error: \(error)")
        }
    }

    private func invokeSendMessageData(_ data: Data) {
        WCSession.default.sendMessageData(data, replyHandler: { (reply) in
            print("reply: \(reply)")
        }) { (error) in
            print("error: \(error)")
        }
    }

    /**
     pass received data to delegate after set delegate
     */
    private func invokeReceivedTasks() {
        if let delegate = delegate {
            DispatchQueue.main.async {
                for task in self.receivedTasks {
                    delegate.connectivity(self, updatedWithTask: task)
                }
                self.receivedTasks.removeAll()
            }
        }
    }
}

#if os(watchOS)
    extension SwiftWatchConnectivity {
        public func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
            for task in backgroundTasks {
                // Use a switch statement to check the task type
                switch task {
                case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
                    self.backgroundTasks.append(connectivityTask)
                default:
                    break
                }
            }
            completeAllTasksIfReady()
        }

        public func completeAllTasksIfReady() {
            let session = WCSession.default
            // the session's properties only have valid values if the session is activated, so check that first
            if session.activationState == .activated && !session.hasContentPending {
                backgroundTasks.forEach { $0.setTaskCompletedWithSnapshot(false) }
                backgroundTasks.removeAll()
            }
        }
    }
#endif

extension SwiftWatchConnectivity: WCSessionDelegate {
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print(error)
            return
        }
        print("activationState: \(activationState.rawValue)")
        self.activationState = activationState
    }
    #if os(iOS)
    public func sessionDidDeactivate(_ session: WCSession) {
        activationState = .notActivated
        print("deactivated")
    }

    public func sessionDidBecomeInactive(_ session: WCSession) {
        activationState = .inactive
        print("inactivated")
    }

    public func sessionWatchStateDidChange(_ session: WCSession) {
        invoke()
        print("state changed")
    }
    #endif

    public func sessionReachabilityDidChange(_ session: WCSession) {
        invoke()
        print("reachability changed")
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        print("applicationContext: \(applicationContext)")
        receivedTasks.append(.updateApplicationContext(applicationContext))
        invokeReceivedTasks()
    }
    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        print("userInfo: \(userInfo)")
        receivedTasks.append(.transferUserInfo(userInfo))
        invokeReceivedTasks()
    }
    public func session(_ session: WCSession, didReceive file: WCSessionFile) {
        print("receiveFile: \(file)")
        receivedTasks.append(.transferFile(file.fileURL, file.metadata))
        invokeReceivedTasks()
    }
    public func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        print("message: \(message)")
        #if os(watchOS)
            let device = "watch"
        #else
            let device = "iPhone"
        #endif
        receivedTasks.append(.sendMessage(message))
        replyHandler(["messageReply": "reply from \(device)"])
        invokeReceivedTasks()
    }
    public func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
        print("messageData: \(messageData)")
        replyHandler(Data())
        receivedTasks.append(.sendMessageData(messageData))
        invokeReceivedTasks()
    }
}

