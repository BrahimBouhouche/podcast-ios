//
//  DownloadManager.swift
//  Recast
//
//  Created by Mindy Lou on 9/17/18.
//  Copyright © 2018 Cornell AppDev. All rights reserved.
//

import Foundation
import CoreData
import UIKit

// Notification names for receiving download progress
// Views can register to listen for these notifications
extension Notification.Name {
    static let didCompleteDownload = Notification.Name("didCompleteDownload")
    static let didFailDownload = Notification.Name("didFailDownload")
    static let didUpdateDownloadProgress = Notification.Name("didUpdateDownloadProgress")
}

class DownloadManager: NSObject {

    static let shared = DownloadManager()

    private override init() {
        super.init()
    }

    lazy private var session: URLSession = {
        // Note: by default, allowsCellularAccess is false
        // We can prompt the user in the future if they want to download over cellular
        // and save it in settings somehow
        let configuration = URLSessionConfiguration.background(withIdentifier:
            "\(Bundle.main.bundleIdentifier ?? "").background" )
        configuration.httpMaximumConnectionsPerHost = 5 // Maximum 5 downloads at once

        // Warning: If an URLSession still exists from a previous download, it doesn't create
        // a new URLSession object but returns the existing one with the old delegate object attached
        return URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue())
    }()

    lazy private var backgroundManagedObjectContext: NSManagedObjectContext = {
        let moc = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        moc.parent = AppDelegate.appDelegate.dataController.managedObjectContext
        return moc
    }()

    /// Maps task handling the download to the download task
    private var downloadedUrls: [URLSessionDownloadTask: URL] = [:]

    func download(episode: Episode, registerObserver: (() -> Void)? = nil) {
        guard let url = episode.enclosure?.url,
            let podcast = episode.podcast,
            let items = podcast.items?.array as? [Episode] else { return }

        let task = session.downloadTask(with: url)
        downloadedUrls[task] = url
        episode.insert(into: backgroundManagedObjectContext)
        podcast.insert(into: backgroundManagedObjectContext)
        // need to fetch episodes and maintain all downloaded eps
//        let episodes = Episode.fetchEpisodes(for: podcast)
        let notDownloadedEpisodes = items.filter { $0.downloadInfo == nil && $0 != episode }
        podcast.removeFromItems(NSOrderedSet(array: notDownloadedEpisodes))
        episode.setValue(podcast, for: .podcast)

        let downloadInfo = DownloadInfo(context: backgroundManagedObjectContext)
        downloadInfo.setValuesForKeys([
            DownloadInfo.Keys.progress.rawValue: 0,
            DownloadInfo.Keys.identifier.rawValue: task.taskIdentifier,
            DownloadInfo.Keys.episode.rawValue: episode,
            DownloadInfo.Keys.status.rawValue: "downloading"
            ])
        episode.setValue(downloadInfo, forKey: Episode.Keys.downloadInfo.rawValue)

        DispatchQueue.main.async {
            registerObserver?()
        }

        do {
            try downloadInfo.validateForInsert()
            try episode.validateForInsert()
            try podcast.validateForInsert()
            save()
        } catch {
            let validationError = error as NSError
            print(validationError)
        }
        task.resume()
    }

    func cancel(episode: Episode) {
        guard let url = episode.enclosure?.url else { return }
        // swiftlint:disable:next opening_brace
        let taskForURL = downloadedUrls.filter{ $0.value == url }.map{ $0.key }.first
        guard let task = taskForURL else { return }
        task.cancel(byProducingResumeData: { resumeData in
            // store resumeData in DownloadInfo
            if let data = resumeData,
                let downloadInfo = DownloadInfo.fetchDownloadInfo(with: task.taskIdentifier, from: self.backgroundManagedObjectContext) {
                let progress = Float(task.countOfBytesReceived) / Float(task.countOfBytesExpectedToReceive)
                downloadInfo.setValuesForKeys([
                    DownloadInfo.Keys.resumeData.rawValue: data,
                    DownloadInfo.Keys.status.rawValue: DownloadInfoStatus.canceled,
                    DownloadInfo.Keys.progress.rawValue: progress
                    ])
                self.save()
            }
        })
    }

    func resume(episode: Episode) {
        guard let url = episode.enclosure?.url, let downloadInfo = episode.downloadInfo,
            let resumeData = downloadInfo.resumeData else { return }
        let task = session.downloadTask(withResumeData: resumeData as Data)
        downloadedUrls[task] = url
        downloadInfo.setValue(task.taskIdentifier, forKey: DownloadInfo.Keys.identifier.rawValue)
        save()
    }

    func save() {
        backgroundManagedObjectContext.perform {
            do {
                if self.backgroundManagedObjectContext.hasChanges {
                    try self.backgroundManagedObjectContext.save()
                    AppDelegate.appDelegate.dataController.saveData()
                }
            } catch {
                let saveError = error as NSError
                print("\(saveError): \(saveError.localizedDescription)")
            }
        }
    }
}

// MARK: - URLSessionDownload Delegate
extension DownloadManager: URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let downloadURL = downloadedUrls[downloadTask],
            let downloadInfo = DownloadInfo.fetchDownloadInfo(with: downloadTask.taskIdentifier, from: backgroundManagedObjectContext)
            else { return }
        downloadInfo.setValuesForKeys([
            DownloadInfo.Keys.downloadedAt.rawValue: Date(), // Current time
            DownloadInfo.Keys.path.rawValue: location.path,
            DownloadInfo.Keys.sizeInBytes.rawValue: downloadTask.countOfBytesReceived,
            DownloadInfo.Keys.status.rawValue: DownloadInfoStatus.succeeded
            ])
        save()
        // Send notification that download is complete
        // Do we need to send user info?
        let userInfoDict = ["url": downloadURL]
        NotificationCenter.default.post(name: .didCompleteDownload, object: nil, userInfo: userInfoDict)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if let downloadURL = downloadedUrls[downloadTask], totalBytesExpectedToWrite > 0 {
            let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
            let userInfoDict: [String: Any] = ["progress": progress, "url": downloadURL]
            // Send download progress notification
            NotificationCenter.default.post(name: .didUpdateDownloadProgress, object: nil, userInfo: userInfoDict)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }
        print("Task failed with error: \(error.localizedDescription)")
        // Fetch download info by identifier
        if let downloadInfo = DownloadInfo.fetchDownloadInfo(with: task.taskIdentifier, from: backgroundManagedObjectContext) {
            downloadInfo.setValue(DownloadInfoStatus.failed, forKey: DownloadInfo.Keys.status.rawValue)
            save()
        }
        // Send notification about error
        guard let downloadTask = task as? URLSessionDownloadTask,
            let downloadURL = downloadedUrls[downloadTask] else { return }
        let userInfoDict = ["url": downloadURL]
        NotificationCenter.default.post(name: .didFailDownload, object: nil, userInfo: userInfoDict)
    }

}
