import 'package:agent_dance/agents/viewmodels/app_viewmodels.dart';
import 'package:agent_dance/agents/viewmodels/server_chat_list_viewmodel.dart';
import 'package:agent_dance/config/app_config.dart';
import 'package:agent_dance/services/app_services.dart';
import 'package:agent_dance/services/background_task_service.dart';
import 'package:agent_dance/ui/agentui/agent_list_screen.dart';
import 'package:agent_dance/ui/discoverui/discover_screen.dart';
import 'package:agent_dance/ui/profileui/profile_screen.dart';
import 'package:agent_dance/ui/serverui/server_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// 底部 4 Tab 主壳
class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  late final AppDatabaseHolder _dbHolder;
  late final ServerChatListViewModel _serverChatListVm;
  late final ServerListViewModel _serverListVm;
  late final DiscoverViewModel _discoverVm;
  late final ProfileViewModel _profileVm;

  @override
  void initState() {
    super.initState();
    final services = AppServices.instance;
    _dbHolder = AppDatabaseHolder(services.db);
    _serverChatListVm = ServerChatListViewModel(
      serverRepository: services.serverRepository,
      sessionRepository: services.sessionRepository,
    );
    _serverListVm = ServerListViewModel(serverRepository: services.serverRepository);
    _discoverVm = DiscoverViewModel(serverRepository: services.serverRepository);
    _profileVm = ProfileViewModel(dbHolder: _dbHolder);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppServices.instance.onAppReady();
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.instance;
    final pages = [
      AgentListScreen(
        viewModel: _serverChatListVm,
        chatRepository: services.chatRepository,
        sessionRepository: services.sessionRepository,
      ),
      ServerListScreen(
        viewModel: _serverListVm,
        sessionRepository: services.sessionRepository,
        chatRepository: services.chatRepository,
      ),
      DiscoverScreen(viewModel: _discoverVm),
      ProfileScreen(
        viewModel: _profileVm,
        onThemeChanged: widget.onThemeChanged,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          if (i == 0) {
            _serverChatListVm.loadServers();
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat), label: '聚智'),
          NavigationDestination(icon: Icon(Icons.dns), label: '服务器'),
          NavigationDestination(icon: Icon(Icons.explore), label: '发现AI'),
          NavigationDestination(icon: Icon(Icons.person), label: '我'),
        ],
      ),
    );
  }
}

/// MaterialApp 入口
class AgentDanceApp extends StatefulWidget {
  const AgentDanceApp({super.key});

  @override
  State<AgentDanceApp> createState() => _AgentDanceAppState();
}

class _AgentDanceAppState extends State<AgentDanceApp> with WidgetsBindingObserver {
  ThemeMode _themeMode = AppConfig.themeMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final inForeground = state == AppLifecycleState.resumed;
    BackgroundTaskService.instance.setAppInForeground(inForeground);
    if (inForeground) {
      AppServices.instance.onAppReady();
    }
  }

  void _onThemeChanged(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
        navigatorKey: AppServices.instance.navigatorKey,
        title: '聚智',
        debugShowCheckedModeBanner: false,
        themeMode: _themeMode,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: MainShell(
          themeMode: _themeMode,
          onThemeChanged: _onThemeChanged,
        ),
      ),
    );
  }
}
