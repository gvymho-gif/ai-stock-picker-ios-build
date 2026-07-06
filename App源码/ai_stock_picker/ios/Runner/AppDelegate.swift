import UIKit
import Flutter
import BackgroundTasks

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // 注册后台任务
    if #available(iOS 13.0, *) {
      BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.aistockpicker.expertPerformance", using: nil) { task in
        self.handleExpertPerformanceTask(task: task as! BGProcessingTask)
      }
      BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.aistockpicker.backgroundFetch", using: nil) { task in
        self.handleBackgroundFetch(task: task as! BGAppRefreshTask)
      }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  @available(iOS 13.0, *)
  func handleExpertPerformanceTask(task: BGProcessingTask) {
    // 专家选股后台定时任务
    let controller = window?.rootViewController as? FlutterViewController
    let channel = FlutterMethodChannel(
      name: "com.aistockpicker/expert_performance",
      binaryMessenger: controller?.binaryMessenger ?? (self as FlutterBinaryMessenger)
    )
    
    task.expirationHandler = {
      task.setTaskCompleted(success: false)
    }
    
    channel.invokeMethod("runExpertPerformance", arguments: nil) { result in
      task.setTaskCompleted(success: true)
    }
  }
  
  @available(iOS 13.0, *)
  func handleBackgroundFetch(task: BGAppRefreshTask) {
    let controller = window?.rootViewController as? FlutterViewController
    let channel = FlutterMethodChannel(
      name: "com.aistockpicker/background_fetch",
      binaryMessenger: controller?.binaryMessenger ?? (self as FlutterBinaryMessenger)
    )
    
    task.expirationHandler = {
      task.setTaskCompleted(success: false)
    }
    
    channel.invokeMethod("performBackgroundFetch", arguments: nil) { result in
      task.setTaskCompleted(success: true)
    }
    
    // 预约下一次后台刷新
    if #available(iOS 13.0, *) {
      let request = BGAppRefreshTaskRequest(identifier: "com.aistockpicker.backgroundFetch")
      request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60) // 30分钟
      try? BGTaskScheduler.shared.submit(request)
    }
  }
}
