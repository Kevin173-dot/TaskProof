import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'new_task_page.dart';

// =============================================================
// MAIN PAGE
// =============================================================

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() =>
      _MainPageState();
}

class _MainPageState
    extends State<MainPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey =
      GlobalKey<ScaffoldState>();

  final List<TaskData> tasks = [];

  int selectedTab = 0;
  int selectedBottomTab = 0;

  bool showCreateMenu = false;

  // ===========================================================
  // DARK MODE
  // ===========================================================

  bool isDarkMode = false;

  Timer? _ticker;

  // ===========================================================
  // LIFE CYCLE
  // ===========================================================

  @override
  void initState() {
    super.initState();

    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        _updateTimers();
      },
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // ===========================================================
  // TIMER
  // ===========================================================

  void _updateTimers() {
    if (!mounted) {
      return;
    }

    final now = DateTime.now();

    final dueTasks = <TaskData>[];

    for (final task in tasks) {
      // =======================================================
      // LIVE SESSION FINISHED
      // =======================================================

      if (task.status == TaskStatus.live) {
        final remaining =
            _remainingLiveTime(task);

        if (remaining <= Duration.zero) {
          task.status = TaskStatus.completed;
          task.completedAt = now;
          task.startedAt = null;
        }
      }

      // =======================================================
      // SCHEDULE REACHED
      // DO NOT AUTO START CAMERA.
      // =======================================================

      if (task.status ==
              TaskStatus.scheduled &&
          task.scheduledFor != null &&
          !task.scheduledFor!.isAfter(now) &&
          !task.scheduleAlertShown) {
        task.scheduleAlertShown = true;

        dueTasks.add(task);
      }
    }

    setState(() {});

    for (final task in dueTasks) {
      WidgetsBinding.instance
          .addPostFrameCallback(
        (_) {
          if (!mounted) {
            return;
          }

          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                duration:
                    const Duration(
                  seconds: 5,
                ),
                content: Text(
                  '${task.name} is scheduled to start now.',
                ),
                action: SnackBarAction(
                  label: 'START',
                  onPressed: () {
                    _startTask(task);
                  },
                ),
              ),
            );
        },
      );
    }
  }

  // ===========================================================
  // ACTIVE TASK
  // ===========================================================

  TaskData? get activeTask {
    for (final task in tasks) {
      if (task.status == TaskStatus.live) {
        return task;
      }
    }

    return null;
  }

  // ===========================================================
  // VERIFIED TODAY
  // ===========================================================

  int get verifiedToday {
    final now = DateTime.now();

    return tasks.where(
      (task) {
        final completed = task.completedAt;

        if (completed == null) {
          return false;
        }

        return completed.year == now.year &&
            completed.month == now.month &&
            completed.day == now.day;
      },
    ).length;
  }

  // ===========================================================
  // BUILD
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF090D12) : const Color(0xFFF5F5F7),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 460,
          ),
          child: Theme(
            data: isDarkMode
                ? ThemeData.dark().copyWith(
                    scaffoldBackgroundColor: const Color(0xFF0B1016),
                    canvasColor: const Color(0xFF10161D),
                    cardColor: const Color(0xFF10161D),
                    dividerColor: const Color(0xFF252D37),
                    colorScheme: const ColorScheme.dark(
                      primary: _C.red,
                      surface: Color(0xFF10161D),
                    ),
                  )
                : ThemeData.light(),
            child: Scaffold(
            key: _scaffoldKey,
            backgroundColor: isDarkMode ? const Color(0xFF0B1016) : Colors.white,
            drawer: const _AppDrawer(),
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _buildHeader(),

                  const SizedBox(height: 10),

                  Expanded(
                    child: _buildTaskArea(),
                  ),
                ],
              ),
            ),
            bottomNavigationBar:
                _buildBottomNavigation(),
          ),
          ),
        ),
      ),
    );
  }

  // ===========================================================
  // HEADER
  // ===========================================================

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        20,
        14,
        20,
        0,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    showCreateMenu = false;
                  });

                  _scaffoldKey.currentState
                      ?.openDrawer();
                },
                icon: Icon(
                  Icons.menu_rounded,
                  color: isDarkMode ? const Color(0xFFF4F6F8) : Colors.black,
                  size: 36,
                ),
              ),

              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: isDarkMode ? 'Switch to light mode' : 'Switch to dark mode',
                    onPressed: () {
                      setState(() {
                        isDarkMode = !isDarkMode;
                        showCreateMenu = false;
                      });
                    },
                    icon: Icon(
                      isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                      color: isDarkMode ? const Color(0xFFF4F6F8) : Colors.black,
                      size: 31,
                    ),
                  ),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        onPressed: _showNotifications,
                        icon: Icon(
                          Icons.notifications_none_rounded,
                          color: isDarkMode ? const Color(0xFFF4F6F8) : Colors.black,
                          size: 35,
                        ),
                      ),
                      Positioned(
                        right: 8,
                        top: 5,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: _C.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 42),

          Text(
            'My Tasks',
            style: TextStyle(
              fontSize: 34,
              height: 1,
              color: isDarkMode ? const Color(0xFFF4F6F8) : _C.dark,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
            ),
          ),

          const SizedBox(height: 15),

          Row(
            children: [
              _VerificationIcon(
                color: isDarkMode ? const Color(0xFF9DA8B8) : const Color(0xFF777B9F),
                showDot: false,
                size: 23,
              ),

              const SizedBox(width: 8),

              Text(
                '$verifiedToday ${verifiedToday == 1 ? 'task' : 'tasks'} verified today',
                style: TextStyle(
                  color: isDarkMode ? const Color(0xFF9DA8B8) : const Color(0xFF666A95),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          _buildTabs(),
        ],
      ),
    );
  }

  // ===========================================================
  // TABS
  // ===========================================================

  Widget _buildTabs() {
    const labels = [
      'All',
      'Scheduled',
      'Completed',
    ];

    return Container(
      height: 57,
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF10161D) : const Color(0xFFF9F9FB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDarkMode ? const Color(0xFF252D37) : const Color(0xFFE8E9ED),
        ),
      ),
      child: Row(
        children: List.generate(
          labels.length,
          (index) {
            final selected =
                selectedTab == index;

            return Expanded(
              child: GestureDetector(
                behavior:
                    HitTestBehavior.opaque,
                onTap: () {
                  setState(() {
                    selectedTab = index;
                    showCreateMenu = false;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(
                    milliseconds: 170,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? (isDarkMode ? const Color(0xFF171E27) : Colors.white)
                        : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(
                      17,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: Colors.black
                                  .withValues(
                                alpha: .04,
                              ),
                              blurRadius: 10,
                              offset:
                                  const Offset(
                                0,
                                3,
                              ),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    labels[index],
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight:
                          FontWeight.w600,
                      color: selected
                          ? _C.red
                          : (isDarkMode ? const Color(0xFFF4F6F8) : _C.dark),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ===========================================================
  // TASK AREA
  // ===========================================================

  Widget _buildTaskArea() {
    return Stack(
      children: [
        Positioned.fill(
          child: tasks.isEmpty
              ? _buildEmptyContent()
              : _buildTasksContent(),
        ),

        Positioned(
          bottom: 20,
          right: 24,
          child: _buildCreateButton(),
        ),
      ],
    );
  }

  // ===========================================================
  // EMPTY STATE
  // ===========================================================

  Widget _buildEmptyContent() {
    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        return SingleChildScrollView(
          physics:
              const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  constraints.maxHeight,
            ),
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(
                24,
                20,
                24,
                120,
              ),
              child: Column(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/clipboard.png',
                    width: 285,
                    fit: BoxFit.contain,
                    errorBuilder: (
                      context,
                      error,
                      stackTrace,
                    ) {
                      return const SizedBox(
                        width: 285,
                        height: 285,
                        child: Center(
                          child: Icon(
                            Icons
                                .image_not_supported_outlined,
                            size: 50,
                            color: _C.grey,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 22),

                  Text(
                    'No tasks yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDarkMode ? const Color(0xFFF4F6F8) : _C.dark,
                      fontSize: 25,
                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    'Create your first task to start staying accountable.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDarkMode ? const Color(0xFFCAD1DA) : Colors.black,
                      fontSize: 16,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ===========================================================
  // TASK CONTENT
  // ===========================================================

  Widget _buildTasksContent() {
    if (selectedTab == 1) {
      final scheduled = tasks
          .where(
            (task) =>
                task.status ==
                TaskStatus.scheduled,
          )
          .toList();

      if (scheduled.isEmpty) {
        return _buildEmptyFilterState(
          title: 'No scheduled tasks',
          subtitle:
              'Tasks you schedule for later will appear here.',
          icon:
              Icons.calendar_today_outlined,
        );
      }

      return ListView(
        padding: const EdgeInsets.fromLTRB(
          20,
          20,
          20,
          140,
        ),
        physics:
            const BouncingScrollPhysics(),
        children: [
          const _ListSectionTitle(
            'SCHEDULED',
          ),

          const SizedBox(height: 10),

          ...scheduled.map(
            (task) => Padding(
              padding:
                  const EdgeInsets.only(
                bottom: 13,
              ),
              child: _buildTaskCard(task),
            ),
          ),
        ],
      );
    }

    if (selectedTab == 2) {
      final completed = tasks
          .where(
            (task) =>
                task.status ==
                TaskStatus.completed,
          )
          .toList();

      if (completed.isEmpty) {
        return _buildEmptyFilterState(
          title: 'Nothing completed yet',
          subtitle:
              'Completed sessions will appear here.',
          icon: Icons.task_alt_rounded,
        );
      }

      return ListView(
        padding: const EdgeInsets.fromLTRB(
          20,
          20,
          20,
          140,
        ),
        physics:
            const BouncingScrollPhysics(),
        children: [
          const _ListSectionTitle(
            'COMPLETED',
          ),

          const SizedBox(height: 10),

          ...completed.map(
            (task) => Padding(
              padding:
                  const EdgeInsets.only(
                bottom: 13,
              ),
              child: _buildTaskCard(task),
            ),
          ),
        ],
      );
    }

    return _buildAllTasks();
  }

  Widget _buildAllTasks() {
    final live = activeTask;

    final ready = tasks
        .where(
          (task) =>
              task.status ==
              TaskStatus.ready,
        )
        .toList();

    final scheduled = tasks
        .where(
          (task) =>
              task.status ==
              TaskStatus.scheduled,
        )
        .toList();

    final completed = tasks
        .where(
          (task) =>
              task.status ==
              TaskStatus.completed,
        )
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        20,
        20,
        20,
        140,
      ),
      physics:
          const BouncingScrollPhysics(),
      children: [
        // =====================================================
        // LIVE
        // =====================================================

        if (live != null) ...[
          const _ListSectionTitle(
            'LIVE NOW',
            color: _C.red,
          ),

          const SizedBox(height: 10),

          _buildLiveCard(live),

          const SizedBox(height: 22),
        ],

        // =====================================================
        // READY
        // =====================================================

        if (ready.isNotEmpty) ...[
          const _ListSectionTitle(
            'READY',
          ),

          const SizedBox(height: 10),

          ...ready.map(
            (task) => Padding(
              padding:
                  const EdgeInsets.only(
                bottom: 13,
              ),
              child: _buildTaskCard(task),
            ),
          ),

          const SizedBox(height: 8),
        ],

        // =====================================================
        // SCHEDULED
        // =====================================================

        if (scheduled.isNotEmpty) ...[
          const _ListSectionTitle(
            'SCHEDULED',
          ),

          const SizedBox(height: 10),

          ...scheduled.map(
            (task) => Padding(
              padding:
                  const EdgeInsets.only(
                bottom: 13,
              ),
              child: _buildTaskCard(task),
            ),
          ),

          const SizedBox(height: 8),
        ],

        // =====================================================
        // COMPLETED
        // =====================================================

        if (completed.isNotEmpty) ...[
          const _ListSectionTitle(
            'COMPLETED',
          ),

          const SizedBox(height: 10),

          ...completed.map(
            (task) => Padding(
              padding:
                  const EdgeInsets.only(
                bottom: 13,
              ),
              child: _buildTaskCard(task),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyFilterState({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          30,
          60,
          30,
          140,
        ),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 54,
              color: const Color(0xFFB0B2BA),
            ),

            const SizedBox(height: 17),

            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _C.dark,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: _C.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================
  // NORMAL TASK CARD
  // ===========================================================

  Widget _buildTaskCard(
    TaskData task,
  ) {
    final scheduled =
        task.status == TaskStatus.scheduled;

    final completed =
        task.status == TaskStatus.completed;

    return Material(
      color: isDarkMode ? const Color(0xFF10161D) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          _showTaskActions(task);
        },
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDarkMode ? const Color(0xFF252D37) : const Color(0xFFE2E3E7),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: .025,
                ),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // =================================================
              // ICON
              // =================================================

              _MainTaskIcon(
                type: task.icon,
                completed: completed,
              ),

              const SizedBox(width: 14),

              // =================================================
              // DETAILS
              // =================================================

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDarkMode ? const Color(0xFFF4F6F8) : _C.dark,
                        fontSize: 17,
                        fontWeight:
                            FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Row(
                      children: [
                        Icon(
                          completed
                              ? Icons
                                  .check_circle_outline_rounded
                              : Icons
                                  .schedule_rounded,
                          size: 17,
                          color: isDarkMode ? const Color(0xFF9DA8B8) : const Color(
                            0xFF7C808C,
                          ),
                        ),

                        const SizedBox(width: 6),

                        Flexible(
                          child: Text(
                            _primaryTaskText(task),
                            overflow:
                                TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isDarkMode ? const Color(0xFF9DA8B8) : const Color(
                                0xFF686C78,
                              ),
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 5),

                    Row(
                      children: [
                        _VerificationIcon(
                          color: isDarkMode ? const Color(0xFF9DA8B8) : const Color(
                            0xFF888C98,
                          ),
                          size: 17,
                          showDot: false,
                        ),

                        const SizedBox(width: 7),

                        Expanded(
                          child: Text(
                            scheduled
                                ? '${_scheduleCountdownText(task)}  •  ${_verificationName(task)}'
                                : _verificationName(
                                    task,
                                  ),
                            maxLines: 1,
                            overflow:
                                TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheduled &&
                                      _isOverdue(
                                        task,
                                      )
                                  ? _C.red
                                  : (isDarkMode ? const Color(0xFF9DA8B8) : const Color(
                                      0xFF7A7E89,
                                    )),
                              fontSize: 12,
                              fontWeight: scheduled &&
                                      _isOverdue(
                                        task,
                                      )
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // =================================================
              // BADGE
              // =================================================

              if (scheduled)
                _StatusBadge(
                  text: 'Scheduled',
                  dot: true,
                  background: isDarkMode ? const Color(0xFF10233B) : const Color(0xFFEAF1FF),
                  foreground: const Color(0xFF2F83FF),
                )
              else if (completed)
                _StatusBadge(
                  text: 'Completed',
                  check: true,
                  background: isDarkMode ? const Color(0xFF10291B) : const Color(0xFFEAF8EF),
                  foreground: const Color(0xFF35C969),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF999DA7),
                  size: 27,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _primaryTaskText(
    TaskData task,
  ) {
    if (task.status ==
            TaskStatus.scheduled &&
        task.scheduledFor != null) {
      return _formatScheduledTime(
        task.scheduledFor!,
      );
    }

    if (task.status ==
            TaskStatus.completed &&
        task.completedAt != null) {
      return 'Completed ${_formatCompletedTime(task.completedAt!)}';
    }

    return _formatTaskDuration(
      task.duration,
    );
  }

  // ===========================================================
  // LIVE CARD
  // ===========================================================

  Widget _buildLiveCard(
    TaskData task,
  ) {
    final remaining =
        _remainingLiveTime(task);

    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(
            24,
            18,
            16,
            18,
          ),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF151014) : const Color(0xFFFFF1F2),
            borderRadius:
                BorderRadius.circular(20),
            border: Border.all(
              color: isDarkMode ? const Color(0xFF7A2229) : const Color(0xFFFFA1A7),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: _C.red.withValues(
                  alpha: .08,
                ),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment:
                CrossAxisAlignment.center,
            children: [
              _LiveTaskIcon(
                type: task.icon,
              ),

              const SizedBox(width: 15),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        _PulseDot(),

                        SizedBox(width: 7),

                        Text(
                          'LIVE SESSION',
                          style: TextStyle(
                            color: _C.red,
                            fontSize: 12,
                            fontWeight:
                                FontWeight.w800,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 7),

                    Text(
                      task.name,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDarkMode ? const Color(0xFFF4F6F8) : _C.dark,
                        fontSize: 20,
                        fontWeight:
                            FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 18,
                          color: isDarkMode ? const Color(0xFF9DA8B8) : const Color(
                            0xFF757985,
                          ),
                        ),

                        const SizedBox(width: 7),

                        Text(
                          '${_formatCountdown(remaining)} remaining',
                          style: TextStyle(
                            color: isDarkMode ? const Color(0xFF9DA8B8) : const Color(
                              0xFF666A75,
                            ),
                            fontSize: 13,
                            fontWeight:
                                FontWeight.w500,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 7),

                    Row(
                      children: [
                        _VerificationIcon(
                          color: isDarkMode ? const Color(0xFF9DA8B8) : const Color(
                            0xFF777B87,
                          ),
                          size: 18,
                          showDot: false,
                        ),

                        const SizedBox(width: 7),

                        Flexible(
                          child: Text(
                            _verificationName(
                              task,
                            ),
                            style:
                                TextStyle(
                              color: isDarkMode ? const Color(0xFF9DA8B8) : const Color(
                                0xFF686C77,
                              ),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 13),

                    SizedBox(
                      height: 42,
                      child: ElevatedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(
                            context,
                          )
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Your live camera session page will open here.',
                                ),
                              ),
                            );
                        },
                        style:
                            ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: isDarkMode ? Colors.transparent : _C.red,
                          foregroundColor: isDarkMode ? _C.red : Colors.white,
                          side: isDarkMode ? const BorderSide(color: _C.red, width: 1.2) : BorderSide.none,
                          shape:
                              RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(
                              11,
                            ),
                          ),
                        ),
                        child: const Text(
                          'Return to Session',
                          style: TextStyle(
                            fontWeight:
                                FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 4),

              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF70747F),
                size: 27,
              ),
            ],
          ),
        ),

        // Red sticking-out stripe.
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: Container(
            width: 7,
            decoration: const BoxDecoration(
              color: _C.red,
              borderRadius:
                  BorderRadius.horizontal(
                left: Radius.circular(20),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================
  // START SESSION
  // ===========================================================

  void _startTask(
    TaskData task,
  ) {
    final current = activeTask;

    if (current != null &&
        current.id != task.id) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${current.name} is already running. Finish it before starting another task.',
            ),
          ),
        );

      return;
    }

    setState(() {
      task.status = TaskStatus.live;
      task.startedAt = DateTime.now();
      task.completedAt = null;
      task.scheduleAlertShown = true;

      selectedTab = 0;
    });
  }

  Duration _remainingLiveTime(
    TaskData task,
  ) {
    if (task.startedAt == null) {
      return task.duration;
    }

    final elapsed =
        DateTime.now().difference(
      task.startedAt!,
    );

    final remaining =
        task.duration - elapsed;

    if (remaining.isNegative) {
      return Duration.zero;
    }

    return remaining;
  }

  // ===========================================================
  // SCHEDULE COUNTDOWN
  // ===========================================================

  Duration _scheduleDifference(
    TaskData task,
  ) {
    if (task.scheduledFor == null) {
      return Duration.zero;
    }

    return task.scheduledFor!.difference(
      DateTime.now(),
    );
  }

  bool _isOverdue(
    TaskData task,
  ) {
    if (task.status !=
            TaskStatus.scheduled ||
        task.scheduledFor == null) {
      return false;
    }

    return DateTime.now().isAfter(
      task.scheduledFor!,
    );
  }

  String _scheduleCountdownText(
    TaskData task,
  ) {
    final difference =
        _scheduleDifference(task);

    if (difference.isNegative ||
        difference == Duration.zero) {
      final overdue = Duration(
        seconds: difference.inSeconds.abs(),
      );

      return 'Overdue by ${_formatCountdown(overdue)}';
    }

    return 'Starts in ${_formatCountdown(difference)}';
  }

  // ===========================================================
  // TASK ACTIONS
  // ===========================================================

  void _showTaskActions(
    TaskData task,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDarkMode ? const Color(0xFF10161D) : Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(26),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              18,
              4,
              18,
              20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  task.name,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 14),

                ListTile(
                  leading: const Icon(
                    Icons.play_arrow_rounded,
                    color: _C.red,
                  ),
                  title: Text(
                    task.status ==
                            TaskStatus.completed
                        ? 'Start Again'
                        : 'Start Session',
                  ),
                  subtitle: const Text(
                    'Begin camera verification and start the task timer.',
                  ),
                  onTap: () {
                    Navigator.pop(context);

                    _startTask(task);
                  },
                ),

                if (task.status !=
                    TaskStatus.live)
                  ListTile(
                    leading: const Icon(
                      Icons.schedule_rounded,
                    ),
                    title: Text(
                      task.status ==
                              TaskStatus.scheduled
                          ? 'Reschedule'
                          : 'Schedule',
                    ),
                    onTap: () async {
                      Navigator.pop(context);

                      await _scheduleTask(
                        task,
                      );
                    },
                  ),

                if (task.status ==
                    TaskStatus.scheduled)
                  ListTile(
                    leading: const Icon(
                      Icons.event_busy_rounded,
                    ),
                    title: const Text(
                      'Remove Schedule',
                    ),
                    onTap: () {
                      Navigator.pop(context);

                      setState(() {
                        task.status =
                            TaskStatus.ready;
                        task.scheduledFor = null;
                        task.scheduleAlertShown =
                            false;
                      });
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ===========================================================
  // SCHEDULE / RESCHEDULE FROM MAIN PAGE
  // ===========================================================

  Future<void> _scheduleTask(
    TaskData task,
  ) async {
    final now = DateTime.now();

    final today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    DateTime initial =
        task.scheduledFor ??
            now.add(
              const Duration(hours: 1),
            );

    if (initial.isBefore(today)) {
      initial = today;
    }

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: now.add(
        const Duration(days: 1095),
      ),
      builder: (
        context,
        child,
      ) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme:
                const ColorScheme.light(
              primary: _C.red,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (date == null || !mounted) {
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime:
          task.scheduledFor != null
              ? TimeOfDay.fromDateTime(
                  task.scheduledFor!,
                )
              : TimeOfDay.fromDateTime(
                  now.add(
                    const Duration(hours: 1),
                  ),
                ),
      builder: (
        context,
        child,
      ) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme:
                const ColorScheme.light(
              primary: _C.red,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (time == null || !mounted) {
      return;
    }

    final scheduled = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    if (!scheduled.isAfter(
      DateTime.now(),
    )) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Choose a scheduled time in the future.',
            ),
          ),
        );

      return;
    }

    setState(() {
      task.status = TaskStatus.scheduled;
      task.scheduledFor = scheduled;
      task.startedAt = null;
      task.completedAt = null;
      task.scheduleAlertShown = false;

      selectedTab = 1;
    });
  }

  // ===========================================================
  // FORMAT HELPERS
  // ===========================================================

  String _verificationName(
    TaskData task,
  ) {
    if (task.stayInPosition &&
        task.objectInFrame) {
      return 'Dual Verification';
    }

    if (task.stayInPosition) {
      return 'Stay in Position';
    }

    if (task.objectInFrame) {
      return 'Object in Frame';
    }

    return 'No Verification';
  }

  String _formatCountdown(
    Duration duration,
  ) {
    int total = duration.inSeconds;

    if (total < 0) {
      total = 0;
    }

    final hours = total ~/ 3600;
    final minutes =
        (total % 3600) ~/ 60;
    final seconds = total % 60;

    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  String _formatTaskDuration(
    Duration duration,
  ) {
    final hours = duration.inHours;
    final minutes =
        duration.inMinutes.remainder(60);

    if (hours > 0 && minutes > 0) {
      return '${hours}h ${minutes}m';
    }

    if (hours > 0) {
      return '${hours}h 00m';
    }

    if (minutes > 0) {
      return '${minutes}m';
    }

    return '${duration.inSeconds}s';
  }

  String _formatScheduledTime(
    DateTime time,
  ) {
    final now = DateTime.now();

    final tomorrow = now.add(
      const Duration(days: 1),
    );

    String day;

    if (DateUtils.isSameDay(
      time,
      now,
    )) {
      day = 'Today';
    } else if (DateUtils.isSameDay(
      time,
      tomorrow,
    )) {
      day = 'Tomorrow';
    } else {
      day =
          '${time.month}/${time.day}/${time.year}';
    }

    return '$day, ${_formatClock(time)}';
  }

  String _formatCompletedTime(
    DateTime time,
  ) {
    final now = DateTime.now();

    if (DateUtils.isSameDay(
      time,
      now,
    )) {
      return 'today, ${_formatClock(time)}';
    }

    final yesterday = now.subtract(
      const Duration(days: 1),
    );

    if (DateUtils.isSameDay(
      time,
      yesterday,
    )) {
      return 'yesterday, ${_formatClock(time)}';
    }

    return '${time.month}/${time.day}, ${_formatClock(time)}';
  }

  String _formatClock(
    DateTime date,
  ) {
    int hour = date.hour;

    final minute = date.minute
        .toString()
        .padLeft(
          2,
          '0',
        );

    final suffix =
        hour >= 12 ? 'PM' : 'AM';

    hour %= 12;

    if (hour == 0) {
      hour = 12;
    }

    return '$hour:$minute $suffix';
  }

  // ===========================================================
  // CREATE NEW TASK
  // ===========================================================

  Future<void> _openNewTaskPage() async {
    setState(() {
      showCreateMenu = false;
    });

    final task =
        await Navigator.push<TaskData>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            NewTaskPage(
          isDarkMode: isDarkMode,
        ),
      ),
    );

    if (task == null || !mounted) {
      return;
    }

    setState(() {
      tasks.add(task);

      // Scheduled task opens the Scheduled tab.
      selectedTab =
          task.status == TaskStatus.scheduled
              ? 1
              : 0;
    });
  }

  // ===========================================================
  // CREATE BUTTON
  // ===========================================================

  Widget _buildCreateButton() {
    return SizedBox(
      width: 290,
      height: 240,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomRight,
        children: [
          Positioned(
            bottom: 0,
            right: 0,
            child: SizedBox(
              width: 90,
              height: 90,
              child: FloatingActionButton(
                heroTag: 'taskCreateFab',
                elevation: 8,
                backgroundColor: isDarkMode ? const Color(0xFF171E27) : _C.red,
                foregroundColor: isDarkMode ? _C.red : Colors.white,
                shape: const CircleBorder(),
                onPressed: () {
                  setState(() {
                    showCreateMenu =
                        !showCreateMenu;
                  });
                },
                child:
                    TweenAnimationBuilder<double>(
                  tween: Tween(
                    begin: 0,
                    end:
                        showCreateMenu ? 1 : 0,
                  ),
                  duration: const Duration(
                    milliseconds: 300,
                  ),
                  builder: (
                    context,
                    progress,
                    child,
                  ) {
                    return CustomPaint(
                      painter:
                          _ApertureButtonPainter(
                        progress: progress,
                      ),
                      size:
                          const Size(36, 36),
                    );
                  },
                ),
              ),
            ),
          ),

          if (showCreateMenu)
            Positioned(
              bottom: 105,
              right: 0,
              child: _buildCreateTaskMenu(),
            ),
        ],
      ),
    );
  }

  Widget _buildCreateTaskMenu() {
    return Container(
      width: 290,
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF10161D) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? const Color(0xFF252D37) : const Color(0xFFE7E7EA),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: .10,
            ),
            blurRadius: 25,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _createTaskMenuItem(
            icon: Icons.bolt_rounded,
            title: 'Quick Task',
            subtitle:
                'Create a task in seconds',
            onTap: () {
              setState(() {
                showCreateMenu = false;
              });

              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Quick Task will be added later.',
                    ),
                  ),
                );
            },
          ),

          const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 18,
            ),
            child: Divider(
              height: 1,
            ),
          ),

          _createTaskMenuItem(
            icon: Icons
                .format_list_bulleted_rounded,
            title: 'Task',
            subtitle:
                'Create a custom task',
            onTap: _openNewTaskPage,
          ),
        ],
      ),
    );
  }

  Widget _createTaskMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          splashColor: _C.red.withValues(
            alpha: .12,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 17,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 42,
                  child: Icon(
                    icon,
                    color: _C.red,
                    size: title == 'Quick Task'
                        ? 35
                        : 31,
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isDarkMode ? const Color(0xFFF4F6F8) : _C.dark,
                          fontSize: 17,
                          fontWeight:
                              FontWeight.w700,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        subtitle,
                        style: TextStyle(
                          color: isDarkMode ? const Color(0xFF9DA8B8) : _C.grey,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================
  // BOTTOM NAVIGATION
  // ===========================================================

  Widget _buildBottomNavigation() {
    return Container(
      height: 92,
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF10161D) : Colors.white,
        borderRadius:
            const BorderRadius.vertical(
          top: Radius.circular(25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: .045,
            ),
            blurRadius: 18,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _bottomItem(
              index: 0,
              icon: Icons.task_alt_rounded,
              label: 'Tasks',
            ),

            _bottomItem(
              index: 1,
              icon: Icons.schedule_rounded,
              label: 'History',
            ),

            _bottomItem(
              index: 2,
              icon:
                  Icons.settings_outlined,
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final selected =
        selectedBottomTab == index;

    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            selectedBottomTab = index;
            showCreateMenu = false;
          });
        },
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 30,
              color: selected
                  ? _C.red
                  : (isDarkMode ? const Color(0xFF9DA8B8) : _C.grey),
            ),

            const SizedBox(height: 4),

            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    FontWeight.w500,
                color: selected
                    ? _C.red
                    : (isDarkMode ? const Color(0xFF9DA8B8) : _C.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================
  // NOTIFICATIONS
  // ===========================================================

  void _showNotifications() {
    setState(() {
      showCreateMenu = false;
    });

    final overdue = tasks
        .where(
          (task) =>
              task.status ==
                  TaskStatus.scheduled &&
              task.scheduledFor != null &&
              DateTime.now().isAfter(
                task.scheduledFor!,
              ),
        )
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: isDarkMode ? const Color(0xFF10161D) : Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(26),
        ),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            22,
            6,
            22,
            35,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const Text(
                'Notifications',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 22),

              if (overdue.isEmpty)
                const _NotificationRow(
                  icon:
                      Icons.verified_outlined,
                  title:
                      'No notifications yet',
                  subtitle:
                      'Task updates and verification alerts will appear here.',
                )
              else
                ...overdue.map(
                  (task) =>
                      _NotificationRow(
                    icon:
                        Icons.alarm_rounded,
                    title:
                        '${task.name} is overdue',
                    subtitle:
                        'Tap the task to start or reschedule it.',
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================
// TASK ICON
// =============================================================

class _MainTaskIcon
    extends StatelessWidget {
  const _MainTaskIcon({
    required this.type,
    required this.completed,
  });

  final TaskIconType type;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF171E27)
            : (completed ? const Color(0xFFF1FAF4) : const Color(0xFFF7F4F5)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        _taskIconData(type),
        size: 31,
        color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFF4F6F8) : const Color(0xFF25272D),
      ),
    );
  }
}

class _LiveTaskIcon
    extends StatelessWidget {
  const _LiveTaskIcon({
    required this.type,
  });

  final TaskIconType type;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter:
          const _LiveCornersPainter(),
      child: Container(
        width: 68,
        height: 68,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF171E27) : const Color(0xFFFFF7F7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          _taskIconData(type),
          size: 34,
          color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFF4F6F8) : const Color(0xFF202229),
        ),
      ),
    );
  }
}

IconData _taskIconData(
  TaskIconType type,
) {
  switch (type) {
    case TaskIconType.generic:
      return Icons.list_rounded;
    case TaskIconType.study:
      return Icons.menu_book_rounded;
    case TaskIconType.cleaning:
      return Icons.cleaning_services_rounded;
    case TaskIconType.workout:
      return Icons.fitness_center_rounded;
    case TaskIconType.running:
      return Icons.directions_run_rounded;
    case TaskIconType.computer:
      return Icons.laptop_mac_rounded;
    case TaskIconType.cooking:
      return Icons.restaurant_rounded;
    case TaskIconType.laundry:
      return Icons.local_laundry_service_rounded;
    case TaskIconType.meditation:
      return Icons.self_improvement_rounded;
    case TaskIconType.garden:
      return Icons.local_florist_rounded;
    case TaskIconType.sleep:
      return Icons.bed_rounded;
    case TaskIconType.shopping:
      return Icons.shopping_cart_rounded;
    case TaskIconType.hydration:
      return Icons.water_drop_rounded;
    case TaskIconType.health:
      return Icons.medication_rounded;
    case TaskIconType.music:
      return Icons.music_note_rounded;
    case TaskIconType.phone:
      return Icons.phone_rounded;
    case TaskIconType.pet:
      return Icons.pets_rounded;
    case TaskIconType.selfCare:
      return Icons.spa_rounded;
  }
}

// =============================================================
// STATUS BADGE
// =============================================================

class _StatusBadge
    extends StatelessWidget {
  const _StatusBadge({
    required this.text,
    required this.background,
    required this.foreground,
    this.dot = false,
    this.check = false,
  });

  final String text;
  final Color background;
  final Color foreground;

  final bool dot;
  final bool check;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: foreground,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],

          if (check) ...[
            Icon(
              Icons.check_rounded,
              color: foreground,
              size: 14,
            ),
            const SizedBox(width: 4),
          ],

          Text(
            text,
            style: TextStyle(
              color: foreground,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// SECTION LABEL
// =============================================================

class _ListSectionTitle
    extends StatelessWidget {
  const _ListSectionTitle(
    this.text, {
    this.color =
        const Color(0xFF747987),
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: .25,
      ),
    );
  }
}

// =============================================================
// LIVE DOT
// =============================================================

class _PulseDot
    extends StatelessWidget {
  const _PulseDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        color: _C.red,
        shape: BoxShape.circle,
      ),
    );
  }
}

// =============================================================
// VERIFICATION ICON
// =============================================================

class _VerificationIcon
    extends StatelessWidget {
  const _VerificationIcon({
    required this.color,
    this.size = 24,
    this.showDot = true,
  });

  final Color color;
  final double size;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _VerificationPainter(
          color: color,
          showDot: showDot,
        ),
      ),
    );
  }
}

class _VerificationPainter
    extends CustomPainter {
  const _VerificationPainter({
    required this.color,
    required this.showDot,
  });

  final Color color;
  final bool showDot;

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final c = size.width * .29;

    canvas.drawLine(
      Offset(0, c),
      Offset.zero,
      paint,
    );

    canvas.drawLine(
      Offset.zero,
      Offset(c, 0),
      paint,
    );

    canvas.drawLine(
      Offset(size.width - c, 0),
      Offset(size.width, 0),
      paint,
    );

    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width, c),
      paint,
    );

    canvas.drawLine(
      Offset(0, size.height - c),
      Offset(0, size.height),
      paint,
    );

    canvas.drawLine(
      Offset(0, size.height),
      Offset(c, size.height),
      paint,
    );

    canvas.drawLine(
      Offset(
        size.width - c,
        size.height,
      ),
      Offset(
        size.width,
        size.height,
      ),
      paint,
    );

    canvas.drawLine(
      Offset(
        size.width,
        size.height,
      ),
      Offset(
        size.width,
        size.height - c,
      ),
      paint,
    );

    if (showDot) {
      final dot = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(
          size.width / 2,
          size.height / 2,
        ),
        size.width * .15,
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant _VerificationPainter oldDelegate,
  ) {
    return oldDelegate.color != color ||
        oldDelegate.showDot != showDot;
  }
}

// =============================================================
// LIVE CORNERS
// =============================================================

class _LiveCornersPainter
    extends CustomPainter {
  const _LiveCornersPainter();

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final paint = Paint()
      ..color = _C.red
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const inset = 7.0;
    const length = 9.0;

    final left = inset;
    final top = inset;
    final right = size.width - inset;
    final bottom = size.height - inset;

    canvas.drawLine(
      Offset(left, top),
      Offset(left + length, top),
      paint,
    );

    canvas.drawLine(
      Offset(left, top),
      Offset(left, top + length),
      paint,
    );

    canvas.drawLine(
      Offset(right, top),
      Offset(right - length, top),
      paint,
    );

    canvas.drawLine(
      Offset(right, top),
      Offset(right, top + length),
      paint,
    );

    canvas.drawLine(
      Offset(left, bottom),
      Offset(left + length, bottom),
      paint,
    );

    canvas.drawLine(
      Offset(left, bottom),
      Offset(left, bottom - length),
      paint,
    );

    canvas.drawLine(
      Offset(right, bottom),
      Offset(right - length, bottom),
      paint,
    );

    canvas.drawLine(
      Offset(right, bottom),
      Offset(right, bottom - length),
      paint,
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) {
    return false;
  }
}

// =============================================================
// NOTIFICATIONS
// =============================================================

class _NotificationRow
    extends StatelessWidget {
  const _NotificationRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 14,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F7),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: _C.dark,
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _C.grey,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// DRAWER
// =============================================================

class _AppDrawer
    extends StatelessWidget {
  const _AppDrawer();

  @override
  Widget build(BuildContext context) {
    final user =
        FirebaseAuth.instance.currentUser;

    final darkMode = Theme.of(context).brightness == Brightness.dark;

    return Drawer(
      backgroundColor: darkMode ? const Color(0xFF10161D) : Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(22),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: _C.red,
                      borderRadius: BorderRadius.circular(
                        17,
                      ),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),

                  const SizedBox(width: 13),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TaskProof',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight:
                                FontWeight.w800,
                          ),
                        ),

                        const SizedBox(height: 3),

                        Text(
                          user?.email ?? '',
                          overflow:
                              TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _C.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(),

            ListTile(
              leading: const Icon(
                Icons.task_alt_rounded,
              ),
              title: const Text(
                'My Tasks',
              ),
              onTap: () {
                Navigator.pop(context);
              },
            ),

            ListTile(
              leading: const Icon(
                Icons.history_rounded,
              ),
              title: const Text(
                'History',
              ),
              onTap: () {},
            ),

            ListTile(
              leading: const Icon(
                Icons.settings_outlined,
              ),
              title: const Text(
                'Settings',
              ),
              onTap: () {},
            ),

            const Spacer(),

            const Divider(),

            ListTile(
              leading: const Icon(
                Icons.logout_rounded,
                color: _C.red,
              ),
              title: const Text(
                'Log out',
                style: TextStyle(
                  color: _C.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () async {
                Navigator.pop(context);

                await FirebaseAuth.instance.signOut();
              },
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// FAB PAINTER
// =============================================================

class _ApertureButtonPainter
    extends CustomPainter {
  const _ApertureButtonPainter({
    required this.progress,
  });

  final double progress;

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final center = Offset(
      size.width / 2,
      size.height / 2,
    );

    final plusOpacity =
        (1 - progress / .4).clamp(
      0.0,
      1.0,
    );

    final bracketProgress =
        ((progress - .2) / .55).clamp(
      0.0,
      1.0,
    );

    final checkOpacity =
        ((progress - .7) / .3).clamp(
      0.0,
      1.0,
    );

    if (plusOpacity > 0) {
      paint.color = Colors.white.withValues(
        alpha: plusOpacity,
      );

      canvas.drawLine(
        Offset(
          center.dx - 12,
          center.dy,
        ),
        Offset(
          center.dx + 12,
          center.dy,
        ),
        paint,
      );

      canvas.drawLine(
        Offset(
          center.dx,
          center.dy - 12,
        ),
        Offset(
          center.dx,
          center.dy + 12,
        ),
        paint,
      );
    }

    if (bracketProgress > 0) {
      paint.color = Colors.white;

      const gap = 14.0;
      const length = 8.5;

      void bracket(
        double dx,
        double dy,
      ) {
        final target = Offset(
          center.dx + dx * gap,
          center.dy + dy * gap,
        );

        final origin = Offset.lerp(
          center,
          target,
          bracketProgress,
        )!;

        final currentLength =
            length * bracketProgress;

        canvas.drawLine(
          origin,
          origin.translate(
            -dx * currentLength,
            0,
          ),
          paint,
        );

        canvas.drawLine(
          origin,
          origin.translate(
            0,
            -dy * currentLength,
          ),
          paint,
        );
      }

      bracket(-1, -1);
      bracket(1, -1);
      bracket(-1, 1);
      bracket(1, 1);
    }

    if (checkOpacity > 0) {
      paint.color = Colors.white.withValues(
        alpha: checkOpacity,
      );

      final path = Path()
        ..moveTo(
          center.dx - 7,
          center.dy + 2.5,
        )
        ..lineTo(
          center.dx - 1.5,
          center.dy + 7.5,
        )
        ..lineTo(
          center.dx + 9.5,
          center.dy - 4.5,
        );

      canvas.drawPath(
        path,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant _ApertureButtonPainter oldDelegate,
  ) {
    return oldDelegate.progress != progress;
  }
}

// =============================================================
// COLORS
// =============================================================

class _C {
  static const red =
      Color(0xFFFF101C);

  static const dark =
      Color(0xFF15171D);

  static const grey =
      Color(0xFF858995);
}