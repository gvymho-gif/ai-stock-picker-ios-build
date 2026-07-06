/// APP入口 - 蓝图极智
///
/// 年轻化设计 - 支持深色/浅色双主题切换
/// 智能规则引擎深度分析

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'services/theme_service.dart';
import 'services/expert_performance_worker.dart';
import 'services/background_service.dart';
import 'services/hot_investment_service.dart';
import 'services/portfolio_sync_service.dart';
import 'services/lite_investment_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化主题服务
  final themeService = await ThemeService.create();

  // 设置初始状态栏样式
  SystemChrome.setSystemUIOverlayStyle(
    AppTheme.getSystemUiOverlayStyle(themeService.themeMode == ThemeMode.dark
        ? Brightness.dark
        : Brightness.light),
  );

  // 支持横竖屏旋转
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // 注册专家选股后台定时任务（方案B：WorkManager）
  try {
    await ExpertPerformanceWorker.registerTask();
    print('专家选股后台任务已注册');
  } catch (e) {
    print('专家选股后台任务注册失败: $e');
  }

  // 启动常驻后台止盈止损监控（前台服务，App退出后仍运行）
  try {
    await BackgroundStockService().initialize();
    await BackgroundStockService().start();
    print('后台止盈止损监控已启动');
  } catch (e) {
    print('后台止盈止损监控启动失败: $e');
  }

  runApp(ThemeInheritedWidget(
    themeService: themeService,
    child: const AIStockPickerApp(),
  ));
}

/// 主题状态继承组件
class ThemeInheritedWidget extends InheritedWidget {
  final ThemeService themeService;

  const ThemeInheritedWidget({
    Key? key,
    required this.themeService,
    required Widget child,
  }) : super(key: key, child: child);

  static ThemeService of(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<ThemeInheritedWidget>();
    if (widget == null) {
      throw Exception('ThemeInheritedWidget not found in context');
    }
    return widget.themeService;
  }

  @override
  bool updateShouldNotify(ThemeInheritedWidget oldWidget) {
    return themeService.themeMode != oldWidget.themeService.themeMode;
  }
}

class AIStockPickerApp extends StatefulWidget {
  const AIStockPickerApp({Key? key}) : super(key: key);

  @override
  State<AIStockPickerApp> createState() => _AIStockPickerAppState();
}

class _AIStockPickerAppState extends State<AIStockPickerApp>
    with WidgetsBindingObserver {
  StreamSubscription? _bgDataChangedSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 注册服务到 ServiceAccess（供 portfolio_sync_service 在恢复后调用）
    ServiceAccess.register('SpeedInvestmentService', null); // 占位
    ServiceAccess.register('HotInvestmentService', HotInvestmentService());
    ServiceAccess.register('LiteInvestmentService', LiteInvestmentService());

    // 监听后台服务发来的数据变更通知
    _bgDataChangedSub = BackgroundStockService().onDataChanged().listen((data) {
      if (data != null) {
        final module = data['module']?.toString() ?? '';
        debugPrint('[前台] 收到后台数据变更通知: module=$module, changedIds=${data['changedIds']}');
        // 根据模块刷新对应数据（后台 isolate 已写入 SharedPreferences）
        switch (module) {
          case 'hot_investment':
            HotInvestmentService().forceReload();
            break;
          case 'lite_investment':
            LiteInvestmentService().forceReload();
            break;
          case 'expert_performance':
            debugPrint('[前台] 专家表现数据已由后台更新');
            break;
          default:
            HotInvestmentService().forceReload();
            LiteInvestmentService().forceReload();
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 监听主题变化
    final themeService = ThemeInheritedWidget.of(context);
    themeService.addListener(_onThemeChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // App 从后台恢复到前台：强制重新加载所有持久化模块
      // 后台 isolate 可能已执行止盈止损结算、专家表现记录
      debugPrint('[前台] App 恢复到前台，全模块重新加载');
      HotInvestmentService().forceReload();
      LiteInvestmentService().forceReload();
      // 通知后台服务立即执行一次检查
      BackgroundStockService().triggerCheck();
    }
  }

  void _onThemeChanged() {
    final themeService = ThemeInheritedWidget.of(context);
    // 更新状态栏样式
    SystemChrome.setSystemUIOverlayStyle(
      AppTheme.getSystemUiOverlayStyle(
        themeService.themeMode == ThemeMode.dark
            ? Brightness.dark
            : Brightness.light,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bgDataChangedSub?.cancel();
    final themeService = ThemeInheritedWidget.of(context);
    themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeService = ThemeInheritedWidget.of(context);

    return AnimatedBuilder(
      animation: themeService,
      builder: (context, child) {
        return MaterialApp(
          title: '蓝图极智',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeService.themeMode,
          home: const SplashScreen(nextScreen: HomeScreen()),
        );
      },
    );
  }
}
