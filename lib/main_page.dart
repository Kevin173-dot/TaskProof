import 'dart:async';

import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'
    hide InputImage, InputImageMetadata, InputImageFormat, InputImageRotation;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    hide InputImage, InputImageMetadata, InputImageFormat, InputImageRotation;

import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart'
    show DetectionMode, ObjectDetector, ObjectDetectorOptions;

import 'active_verification_page.dart';
import 'new_task_page.dart';
import 'object_recognition_service.dart';
import 'workout_pose_analyzer.dart';
import 'workout_verification_page.dart';

// =============================================================
// MAIN PAGE
// =============================================================

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final List<TaskData> tasks = [];

  late final PageController _taskPageController;

  int selectedTab = 0;

  int selectedBottomTab = 0;

  bool showCreateMenu = false;

  bool isDarkMode = false;

  Timer? _ticker;

  late final ValueNotifier<DateTime> _clock;

  DateTime _displayedDay = DateUtils.dateOnly(DateTime.now());

  // ===========================================================
  // INIT
  // ===========================================================

  @override
  void initState() {
    super.initState();

    _taskPageController = PageController(initialPage: selectedTab);

    _clock = ValueNotifier<DateTime>(DateTime.now());

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateTimers();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();

    _clock.dispose();

    _taskPageController.dispose();

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

    var hasVisibleCountdown = false;

    // MainPage handles scheduled reminders.
    // Live task completion is handled inside
    // LiveVerificationPage so we don't race two timers.

    for (final task in tasks) {
      if ((task.status == TaskStatus.live && task.startedAt != null) ||
          (task.status == TaskStatus.scheduled && task.scheduledFor != null)) {
        hasVisibleCountdown = true;
      }

      if (task.status == TaskStatus.scheduled &&
          task.scheduledFor != null &&
          !task.scheduledFor!.isAfter(now) &&
          !task.scheduleAlertShown) {
        task.scheduleAlertShown = true;

        dueTasks.add(task);
      }
    }

    // Keep checking reminders while another page covers MainPage, but do not
    // rebuild its hidden widget tree. Countdown listeners catch up on the next
    // tick after this route becomes visible again.
    final routeIsVisible = ModalRoute.of(context)?.isCurrent ?? true;

    if (routeIsVisible && hasVisibleCountdown) {
      _clock.value = now;
    }

    final today = DateUtils.dateOnly(now);

    if (routeIsVisible && today != _displayedDay) {
      setState(() {
        _displayedDay = today;
      });
    }

    for (final task in dueTasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 7),
              content: Text('${task.name} is scheduled to start now.'),
              action: SnackBarAction(
                label: 'START',
                onPressed: () {
                  _startTask(task);
                },
              ),
            ),
          );
      });
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

    return tasks.where((task) {
      final completed = task.completedAt;

      if (completed == null) {
        return false;
      }

      return DateUtils.isSameDay(completed, now);
    }).length;
  }

  // ===========================================================
  // BUILD
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    final outerBackground = isDarkMode
        ? const Color(0xFF090D12)
        : const Color(0xFFF5F5F7);

    final pageBackground = isDarkMode ? const Color(0xFF0B1016) : Colors.white;

    return Scaffold(
      backgroundColor: outerBackground,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Theme(
            data: isDarkMode
                ? ThemeData.dark().copyWith(
                    textTheme: GoogleFonts.sourceSans3TextTheme(
                      ThemeData.dark().textTheme,
                    ),
                    scaffoldBackgroundColor: pageBackground,
                    canvasColor: const Color(0xFF10161D),
                    cardColor: const Color(0xFF10161D),
                    dividerColor: const Color(0xFF252D37),
                    colorScheme: ColorScheme.dark(
                      primary: _C.red,
                      surface: const Color(0xFF10161D),
                    ),
                  )
                : ThemeData.light().copyWith(
                    textTheme: GoogleFonts.sourceSans3TextTheme(
                      ThemeData.light().textTheme,
                    ),
                  ),
            child: Scaffold(
              key: _scaffoldKey,
              backgroundColor: pageBackground,
              drawer: _AppDrawer(),
              body: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _buildHeader(),

                    const SizedBox(height: 10),

                    Expanded(child: _buildTaskArea()),
                  ],
                ),
              ),
              bottomNavigationBar: _buildBottomNavigation(),
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
    final textColor = isDarkMode ? const Color(0xFFF4F6F8) : _C.dark;

    final completedToday = verifiedToday;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    showCreateMenu = false;
                  });

                  _scaffoldKey.currentState?.openDrawer();
                },
                icon: Icon(Icons.menu_rounded, color: textColor, size: 36),
              ),

              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: isDarkMode ? 'Light mode' : 'Dark mode',
                    onPressed: () {
                      setState(() {
                        isDarkMode = !isDarkMode;

                        showCreateMenu = false;
                      });
                    },
                    icon: Icon(
                      isDarkMode
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      color: textColor,
                      size: 30,
                    ),
                  ),

                  Stack(
                    children: [
                      IconButton(
                        onPressed: _showNotifications,
                        icon: Icon(
                          Icons.notifications_none_rounded,
                          color: textColor,
                          size: 35,
                        ),
                      ),

                      Positioned(
                        right: 8,
                        top: 5,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
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

          const SizedBox(height: 10),

          Text(
            'My Tasks',
            style: TextStyle(
              color: textColor,
              fontSize: 28,
              height: 1,
              fontFamily: 'Nunito Sans',
              fontWeight: FontWeight.w900,
              letterSpacing: -.7,
            ),
          ),

          const SizedBox(height: 15),

          Row(
            children: [
              Icon(
                Icons.verified_outlined,
                color: isDarkMode
                    ? const Color(0xFF9DA8B8)
                    : const Color(0xFF777B9F),
                size: 21,
              ),

              const SizedBox(width: 8),

              Text(
                '$completedToday ${completedToday == 1 ? 'task' : 'tasks'} verified today',
                style: TextStyle(
                  color: isDarkMode
                      ? const Color(0xFF9DA8B8)
                      : const Color(0xFF666A95),
                  fontSize: 14,
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

  void _selectTaskTab(int index) {
    setState(() {
      selectedTab = index;
      showCreateMenu = false;
    });

    if (_taskPageController.hasClients) {
      _taskPageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }
  // ===========================================================
  // TABS
  // ===========================================================

  Widget _buildTabs() {
    const labels = ['All', 'Scheduled', 'Completed'];

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
        children: List.generate(labels.length, (index) {
          final selected = selectedTab == index;

          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _selectTaskTab(index);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 170),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? isDarkMode
                            ? const Color(0xFF171E27)
                            : Colors.white
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Text(
                  labels[index],
                  style: TextStyle(
                    fontSize: 16,
                    fontFamily: 'Nunito Sans',
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? _C.red
                        : isDarkMode
                        ? const Color(0xFFF4F6F8)
                        : _C.dark,
                  ),
                ),
              ),
            ),
          );
        }),
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
          child: PageView.builder(
            controller: _taskPageController,
            itemCount: 3,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (index) {
              if (selectedTab == index) {
                return;
              }

              setState(() {
                selectedTab = index;
                showCreateMenu = false;
              });
            },
            itemBuilder: (context, index) {
              if (index == 0 && tasks.isEmpty) {
                return _buildEmptyContent();
              }

              return _buildTasksContent(index);
            },
          ),
        ),

        Positioned(bottom: 20, right: 24, child: _buildCreateButton()),
      ],
    );
  }

  // ===========================================================
  // EMPTY STATE
  // ===========================================================

  Widget _buildEmptyContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final decodedClipboardWidth =
            (230 * MediaQuery.devicePixelRatioOf(context))
                .ceil()
                .clamp(230, 920)
                .toInt();

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    isDarkMode
                        ? 'assets/images/clipboard_dark.png'
                        : 'assets/images/clipboard.png',
                    width: 230,
                    fit: BoxFit.contain,
                    cacheWidth: decodedClipboardWidth,
                    errorBuilder: (context, error, stackTrace) {
                      return const SizedBox(
                        width: 180,
                        height: 180,
                        child: Center(
                          child: Icon(
                            Icons.task_alt_rounded,
                            size: 70,
                            color: _C.grey,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  Text(
                    'No tasks yet',
                    style: TextStyle(
                      color: isDarkMode ? Colors.white : _C.dark,
                      fontSize: 25,
                      fontFamily: 'Nunito Sans',
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'Create your first task to start staying accountable.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDarkMode
                          ? const Color(0xFFCAD1DA)
                          : Colors.black,
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

  Widget _buildTasksContent(int tabIndex) {
    if (tabIndex == 1) {
      final scheduled = tasks
          .where((task) => task.status == TaskStatus.scheduled)
          .toList();

      if (scheduled.isEmpty) {
        return _filterEmpty(
          'No scheduled tasks',
          'Tasks you schedule for later will appear here.',
          Icons.calendar_today_outlined,
        );
      }

      return _taskList(scheduled);
    }

    if (tabIndex == 2) {
      final completed = tasks
          .where((task) => task.status == TaskStatus.completed)
          .toList();

      if (completed.isEmpty) {
        return _filterEmpty(
          'Nothing completed yet',
          'Completed sessions will appear here.',
          Icons.task_alt_rounded,
        );
      }

      return _taskList(completed);
    }

    final live = activeTask;

    final ready = tasks
        .where((task) => task.status == TaskStatus.ready)
        .toList();

    final scheduled = tasks
        .where((task) => task.status == TaskStatus.scheduled)
        .toList();

    final completed = tasks
        .where((task) => task.status == TaskStatus.completed)
        .toList();

    final itemBuilders = <WidgetBuilder>[];

    void addSpacer(double height) {
      itemBuilders.add((_) => SizedBox(height: height));
    }

    void addTaskSection(
      String label,
      List<TaskData> sectionTasks, {
      Color? color,
      double trailingSpace = 0,
    }) {
      itemBuilders.add(
        (_) => color == null
            ? _SectionLabel(label)
            : _SectionLabel(label, color: color),
      );
      addSpacer(9);

      for (final task in sectionTasks) {
        itemBuilders.add((_) => _taskPadding(task));
      }

      if (trailingSpace > 0) {
        addSpacer(trailingSpace);
      }
    }

    if (live != null) {
      itemBuilders.add((_) => const _SectionLabel('LIVE NOW', color: _C.red));
      addSpacer(9);
      itemBuilders.add((_) => _buildLiveCard(live));
      addSpacer(22);
    }

    if (ready.isNotEmpty) {
      addTaskSection('READY', ready, trailingSpace: 10);
    }

    if (scheduled.isNotEmpty) {
      addTaskSection('SCHEDULED', scheduled, trailingSpace: 10);
    }

    if (completed.isNotEmpty) {
      addTaskSection('COMPLETED', completed);
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
      itemCount: itemBuilders.length,
      itemBuilder: (context, index) => itemBuilders[index](context),
    );
  }

  Widget _taskList(List<TaskData> list) {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
      itemCount: list.length,
      itemBuilder: (context, index) => _taskPadding(list[index]),
    );
  }

  Widget _taskPadding(TaskData task) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: _buildTaskCard(task),
    );
  }

  Widget _filterEmpty(String title, String subtitle, IconData icon) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: const Color(0xFFB0B2BA)),

            const SizedBox(height: 16),

            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDarkMode ? Colors.white : _C.dark,
                fontSize: 22,
                fontFamily: 'Nunito Sans',
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 7),

            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _C.grey, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================
  // TASK CARD
  // ===========================================================

  Widget _buildTaskCard(TaskData task) {
    final scheduled = task.status == TaskStatus.scheduled;

    final completed = task.status == TaskStatus.completed;

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
              color: isDarkMode
                  ? const Color(0xFF252D37)
                  : const Color(0xFFE2E3E7),
            ),
          ),
          child: Row(
            children: [
              // =================================================
              // ICON
              // =================================================
              Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: completed
                      ? isDarkMode
                            ? const Color(0xFF10291B)
                            : const Color(0xFFF0FAF3)
                      : isDarkMode
                      ? const Color(0xFF171E27)
                      : const Color(0xFFF4F4F6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  taskIconData(task.icon),
                  size: 30,
                  color: isDarkMode ? Colors.white : const Color(0xFF25272D),
                ),
              ),

              const SizedBox(width: 14),

              // =================================================
              // CONTENT
              // =================================================
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDarkMode ? Colors.white : _C.dark,
                        fontSize: 17,
                        fontFamily: 'Nunito Sans',
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      _taskPrimaryText(task),
                      style: TextStyle(
                        color: isDarkMode
                            ? const Color(0xFF9DA8B8)
                            : const Color(0xFF686C78),
                        fontSize: 13,
                      ),
                    ),

                    const SizedBox(height: 4),

                    if (scheduled)
                      ValueListenableBuilder<DateTime>(
                        valueListenable: _clock,
                        builder: (context, now, _) {
                          return Text(
                            '${_scheduleCountdownText(task, now)} • ${_verificationName(task)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _isOverdue(task, now)
                                  ? _C.red
                                  : isDarkMode
                                  ? const Color(0xFF9DA8B8)
                                  : const Color(0xFF777A84),
                              fontSize: 12,
                            ),
                          );
                        },
                      )
                    else
                      Text(
                        _verificationName(task),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDarkMode
                              ? const Color(0xFF9DA8B8)
                              : const Color(0xFF777A84),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // =================================================
              // STATUS
              // =================================================
              if (scheduled)
                const _Badge(
                  text: 'Scheduled',
                  background: Color(0xFFEAF1FF),
                  foreground: Color(0xFF2874E8),
                )
              else if (completed)
                const _Badge(
                  text: 'Completed',
                  background: Color(0xFFEAF8EF),
                  foreground: Color(0xFF249C4A),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF999DA7),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================
  // LIVE CARD
  // ===========================================================

  Widget _buildLiveCard(TaskData task) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 17, 16, 17),
          decoration: BoxDecoration(
            color: isDarkMode
                ? const Color(0xFF151014)
                : const Color(0xFFFFF1F2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDarkMode
                  ? const Color(0xFF7A2229)
                  : const Color(0xFFFFA1A7),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 66,
                height: 66,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF1B1418) : Colors.white,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  taskIconData(task.icon),
                  size: 32,
                  color: isDarkMode ? Colors.white : _C.dark,
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                            fontFamily: 'Nunito Sans',
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    Text(
                      task.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDarkMode ? Colors.white : _C.dark,
                        fontSize: 19,
                        fontFamily: 'Nunito Sans',
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 5),

                    ValueListenableBuilder<DateTime>(
                      valueListenable: _clock,
                      builder: (context, _, child) {
                        return Text(
                          _liveSessionSubtitle(task, remainingLiveTime(task)),
                          style: TextStyle(
                            color: isDarkMode
                                ? const Color(0xFF9DA8B8)
                                : const Color(0xFF666A75),
                            fontSize: 13,
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 10),

                    SizedBox(
                      height: 39,
                      child: ElevatedButton(
                        onPressed: () {
                          _openLiveSession(task);
                        },
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: _C.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text(
                          'Return to Session',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: Container(
            width: 7,
            decoration: const BoxDecoration(
              color: _C.red,
              borderRadius: BorderRadius.horizontal(left: Radius.circular(20)),
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================
  // START TASK
  // ===========================================================

  Future<void> _startTask(TaskData task) async {
    final current = activeTask;

    if (current != null && current.id != task.id) {
      _message(
        '${current.name} is already running. Finish it before starting another task.',
      );

      return;
    }

    // ===========================================================
    // CHECK MODE REQUIREMENTS
    // ===========================================================

    switch (task.mode) {
      case TaskMode.focus:
        if ((task.stayInPosition || task.objectInFrame) &&
            !MlKitCameraImageConverter.supported) {
          _message(
            'Focus camera verification must be tested on Android or iPhone, not Chrome.',
          );

          return;
        }

        break;

      case TaskMode.active:
        if (!MlKitCameraImageConverter.supported) {
          _message('Active verification must be used on Android or iPhone.');

          return;
        }

        if (task.activeConfig == null) {
          _message('This task is missing its Active verification setup.');

          return;
        }

        break;

      case TaskMode.workout:
        if (!MlKitCameraImageConverter.supported) {
          _message('Workout verification must be used on Android or iPhone.');

          return;
        }

        if (task.workoutConfig == null) {
          _message('This task is missing its Workout setup.');

          return;
        }

        break;
    }

    // ===========================================================
    // FOCUS CALIBRATION
    // ===========================================================
    //
    // Every Stay in Position task must have a reference BEFORE
    // LiveVerificationPage opens.
    //
    // This means both:
    //
    // 1. Calibrating while creating the task
    //
    // and
    //
    // 2. Skipping calibration and pressing Start later
    //
    // use the SAME countdown calibration page.
    // ===========================================================

    if (task.mode == TaskMode.focus &&
        task.stayInPosition &&
        task.poseReference == null) {
      final reference = await Navigator.push<PoseReference>(
        context,
        MaterialPageRoute(
          builder: (context) => ReferencePositionPage(
            isDarkMode: isDarkMode,
            focusActivity: task.focusActivity,
          ),
        ),
      );

      // They backed out of calibration.
      // Do NOT start the task.
      if (reference == null || !mounted) {
        return;
      }

      task.poseReference = reference;
    }

    if (!mounted) {
      return;
    }

    // ===========================================================
    // START TASK
    // ===========================================================

    setState(() {
      task.status = TaskStatus.live;

      task.completedAt = null;

      task.scheduleAlertShown = true;

      switch (task.mode) {
        case TaskMode.focus:
          // Focus calibration, when required, has already
          // completed above. Start the timer now.
          task.startedAt = DateTime.now();
          break;

        case TaskMode.active:
          task.startedAt = DateTime.now();
          break;

        case TaskMode.workout:
          // WorkoutVerificationPage controls its own start.
          task.startedAt = null;
          break;
      }
    });

    _selectTaskTab(0);

    await _openLiveSession(task);
  }
  // ===========================================================
  // OPEN LIVE SESSION
  // ===========================================================

  Future<void> _openLiveSession(TaskData task) async {
    if (task.status != TaskStatus.live) {
      return;
    }

    late final Widget page;

    switch (task.mode) {
      case TaskMode.focus:
        page = LiveVerificationPage(task: task, isDarkMode: isDarkMode);
        break;

      case TaskMode.active:
        page = ActiveVerificationPage(task: task, isDarkMode: isDarkMode);
        break;

      case TaskMode.workout:
        page = WorkoutVerificationPage(task: task, isDarkMode: isDarkMode);
        break;
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => page),
    );

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  // ===========================================================
  // TASK ACTIONS
  // ===========================================================

  void _showTaskActions(TaskData task) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDarkMode ? const Color(0xFF10161D) : Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.name,
                  style: const TextStyle(
                    fontSize: 23,
                    fontFamily: 'Nunito Sans',
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 13),

                if (task.status == TaskStatus.live)
                  ListTile(
                    leading: const Icon(Icons.videocam_rounded, color: _C.red),
                    title: const Text('Return to Session'),
                    onTap: () {
                      Navigator.pop(context);

                      _openLiveSession(task);
                    },
                  )
                else
                  ListTile(
                    leading: const Icon(
                      Icons.play_arrow_rounded,
                      color: _C.red,
                    ),
                    title: Text(
                      task.status == TaskStatus.completed
                          ? 'Start Again'
                          : 'Start Session',
                    ),
                    subtitle: const Text(
                      'Begin camera verification and start the timer.',
                    ),
                    onTap: () {
                      Navigator.pop(context);

                      _startTask(task);
                    },
                  ),

                if (task.status != TaskStatus.live)
                  ListTile(
                    leading: const Icon(Icons.schedule_rounded),
                    title: Text(
                      task.status == TaskStatus.scheduled
                          ? 'Reschedule'
                          : 'Schedule',
                    ),
                    onTap: () {
                      Navigator.pop(context);

                      _scheduleTask(task);
                    },
                  ),

                if (task.status == TaskStatus.scheduled)
                  ListTile(
                    leading: const Icon(Icons.event_busy_rounded),
                    title: const Text('Remove Schedule'),
                    onTap: () {
                      Navigator.pop(context);

                      setState(() {
                        task.status = TaskStatus.ready;

                        task.scheduledFor = null;

                        task.scheduleAlertShown = false;
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
  // SCHEDULE
  // ===========================================================

  Future<void> _scheduleTask(TaskData task) async {
    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);

    final initialDate =
        task.scheduledFor != null && !task.scheduledFor!.isBefore(today)
        ? task.scheduledFor!
        : today;

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: DateTime(now.year + 3, 12, 31),
    );

    if (date == null || !mounted) {
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: task.scheduledFor != null
          ? TimeOfDay.fromDateTime(task.scheduledFor!)
          : TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
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

    if (!scheduled.isAfter(DateTime.now())) {
      _message('Choose a scheduled time in the future.');

      return;
    }

    setState(() {
      task.status = TaskStatus.scheduled;

      task.scheduledFor = scheduled;

      task.startedAt = null;

      task.completedAt = null;

      task.scheduleAlertShown = false;
    });

    _selectTaskTab(1);
  }

  // ===========================================================
  // TASK FORMATTERS
  // ===========================================================

  String _taskPrimaryText(TaskData task) {
    if (task.status == TaskStatus.scheduled && task.scheduledFor != null) {
      return formatScheduled(task.scheduledFor!);
    }

    if (task.status == TaskStatus.completed && task.completedAt != null) {
      return 'Completed ${formatClock(task.completedAt!)}';
    }

    final workout = task.workoutConfig;
    if (task.mode == TaskMode.workout && workout != null) {
      final goal = workout.movementType == WorkoutMovementType.repetitions
          ? '${workout.repGoal} reps'
          : formatTaskDuration(workout.targetDuration);
      return '${workoutExerciseLabel(workout.exercise)} • $goal';
    }

    return formatTaskDuration(task.duration);
  }

  String _verificationName(TaskData task) {
    switch (task.mode) {
      case TaskMode.active:
        return 'Active Monitoring';

      case TaskMode.workout:
        return 'Workout Verification';

      case TaskMode.focus:
        if (task.stayInPosition && task.objectInFrame) {
          return 'Dual Verification';
        }

        if (task.stayInPosition) {
          return 'Stay in Focus Area';
        }

        if (task.objectInFrame) {
          return 'Object in Frame';
        }

        return 'No Verification';
    }
  }

  String _liveSessionSubtitle(TaskData task, Duration remaining) {
    if (task.startedAt != null) {
      return '${formatCountdown(remaining)} remaining';
    }

    return switch (task.mode) {
      TaskMode.focus => 'Waiting for position calibration',
      TaskMode.active => 'Preparing active verification',
      TaskMode.workout => 'Preparing workout verification',
    };
  }

  bool _isOverdue(TaskData task, [DateTime? now]) {
    return task.status == TaskStatus.scheduled &&
        task.scheduledFor != null &&
        (now ?? DateTime.now()).isAfter(task.scheduledFor!);
  }

  String _scheduleCountdownText(TaskData task, [DateTime? now]) {
    if (task.scheduledFor == null) {
      return '';
    }

    final difference = task.scheduledFor!.difference(now ?? DateTime.now());

    if (difference.isNegative) {
      return 'Overdue by ${formatCountdown(Duration(seconds: difference.inSeconds.abs()))}';
    }

    return 'Starts in ${formatCountdown(difference)}';
  }

  // ===========================================================
  // NEW TASK
  // ===========================================================

  Future<void> _openNewTaskPage() async {
    setState(() {
      showCreateMenu = false;
    });

    final task = await Navigator.push<TaskData>(
      context,
      MaterialPageRoute(
        builder: (context) => NewTaskPage(isDarkMode: isDarkMode),
      ),
    );

    if (task == null || !mounted) {
      return;
    }

    setState(() {
      tasks.add(task);
    });

    _selectTaskTab(task.status == TaskStatus.scheduled ? 1 : 0);
  }

  // ===========================================================
  // CREATE FAB
  // ===========================================================

  Widget _buildCreateButton() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (showCreateMenu) ...[_buildCreateMenu(), const SizedBox(height: 16)],

        SizedBox(
          width: 78,
          height: 78,
          child: FloatingActionButton(
            heroTag: 'taskCreateFab',
            elevation: 8,
            backgroundColor: _C.red,
            foregroundColor: Colors.white,
            shape: const CircleBorder(),
            onPressed: () {
              setState(() {
                showCreateMenu = !showCreateMenu;
              });
            },
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: showCreateMenu ? 1 : 0),
              duration: const Duration(milliseconds: 300),
              builder: (context, progress, child) {
                return CustomPaint(
                  painter: _ApertureButtonPainter(progress: progress),
                  size: const Size(32, 32),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCreateMenu() {
    return Container(
      width: 285,
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF10161D) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? const Color(0xFF252D37) : const Color(0xFFE7E7EA),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: .12), blurRadius: 22),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.bolt_rounded, color: _C.red),
            title: const Text('Quick Task'),
            subtitle: const Text('Create a task in seconds'),
            onTap: () {
              setState(() {
                showCreateMenu = false;
              });

              _message('Quick Task will be added later.');
            },
          ),

          const Divider(height: 1),

          ListTile(
            leading: const Icon(
              Icons.format_list_bulleted_rounded,
              color: _C.red,
            ),
            title: const Text('Task'),
            subtitle: const Text('Create a custom task'),
            onTap: _openNewTaskPage,
          ),
        ],
      ),
    );
  }

  // ===========================================================
  // BOTTOM NAV
  // ===========================================================

  Widget _buildBottomNavigation() {
    return Container(
      height: 92,
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF10161D) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _bottomItem(0, Icons.task_alt_rounded, 'Tasks'),

            _bottomItem(1, Icons.history_rounded, 'History'),

            _bottomItem(2, Icons.settings_outlined, 'Settings'),
          ],
        ),
      ),
    );
  }

  Widget _bottomItem(int index, IconData icon, String label) {
    final selected = selectedBottomTab == index;

    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            selectedBottomTab = index;

            showCreateMenu = false;
          });
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? _C.red : _C.grey, size: 29),

            const SizedBox(height: 4),

            Text(
              label,
              style: TextStyle(
                color: selected ? _C.red : _C.grey,
                fontSize: 13,
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
    final overdue = tasks.where(_isOverdue).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: isDarkMode ? const Color(0xFF10161D) : Colors.white,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Notifications',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
                ),

                const SizedBox(height: 15),

                if (overdue.isEmpty)
                  const ListTile(
                    leading: Icon(Icons.notifications_none_rounded),
                    title: Text('No notifications yet'),
                  )
                else
                  ...overdue.map(
                    (task) => ListTile(
                      leading: const Icon(Icons.alarm_rounded, color: _C.red),
                      title: Text('${task.name} is overdue'),
                      subtitle: const Text('Start it now or reschedule.'),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

// =============================================================
// LIVE VERIFICATION PAGE
// =============================================================

class LiveVerificationPage extends StatefulWidget {
  const LiveVerificationPage({
    super.key,
    required this.task,
    required this.isDarkMode,
  });

  final TaskData task;

  final bool isDarkMode;

  @override
  State<LiveVerificationPage> createState() => _LiveVerificationPageState();
}

class _LiveVerificationPageState extends State<LiveVerificationPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _controller;

  CameraDescription? _camera;

  PoseDetector? _poseDetector;

  FaceDetector? _faceDetector;

  ObjectDetector? _objectLocator;

  final ObjectRecognitionService _objectRecognition = ObjectRecognitionService(
    analysisInterval: const Duration(milliseconds: 450),
    hitConfirmationFrames: 3,
  );
  Timer? _timer;

  late final AnimationController _recheckFlashController;

  late final ValueNotifier<Duration> _remainingTime;

  late final VerificationThresholds _thresholds;

  static const Color _verifiedGreen = Color(0xFF22C55E);

  static const double _objectInitialMatchConfidence = 0.84;
  static const double _objectOngoingMatchConfidence = 0.80;

  bool _cameraInitializing = true;

  bool _startingCamera = false;

  bool _processing = false;

  bool _warningActive = false;

  bool _hasBeenMonitoring = false;

  bool _leftAppWhileMonitoring = false;

  // ===========================================================
  // PAUSE STATE
  // ===========================================================

  bool _userPaused = false;

  bool _pauseTransitionRunning = false;

  Duration? _pausedRemaining;

  String _status = 'Preparing verification...';

  String? _warningReason;

  PoseReference? _latestPose;

  PoseReference? _previousFocusPose;

  final List<PoseReference> _liveCalibrationSamples = <PoseReference>[];

  bool _liveCalibrationReady = false;

  double _handMotionEma = 0.0;

  DateTime? _fidgetStartedAt;

  DateTime? _violationStartedAt;

  DateTime? _recoveryStartedAt;

  bool get _isRechecking => _warningActive && _recoveryStartedAt != null;

  DateTime _lastAnalysis = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime _lastFaceAnalysis = DateTime.fromMillisecondsSinceEpoch(0);

  List<Face> _latestFaces = const [];

  final List<_FocusRequiredObjectState> _requiredObjects = [];

  bool _objectProfilesReady = false;

  DateTime? _objectMonitoringStartedAt;

  bool get _requiredObjectsVerifiedNow {
    if (!widget.task.objectInFrame) {
      return true;
    }

    if (!_objectProfilesReady || _requiredObjects.isEmpty) {
      return false;
    }

    final now = DateTime.now();

    return _requiredObjects.every((object) {
      if (!object.available) {
        return false;
      }

      final lastMatchedAt = object.lastMatchedAt;

      if (lastMatchedAt == null) {
        return false;
      }

      return now.difference(lastMatchedAt) < _objectMissingGrace;
    });
  }

  String get _requiredObjectPrompt {
    if (!_objectProfilesReady) {
      return 'Loading required object...';
    }

    if (_requiredObjects.isEmpty) {
      return 'Required object is unavailable';
    }

    if (_requiredObjects.length == 1) {
      return 'Show ${_requiredObjects.first.name} in frame';
    }

    return 'Show required objects in frame';
  }

  String get _requiredObjectVerifiedLabel {
    if (_requiredObjects.length == 1) {
      return '${_requiredObjects.first.name} verified';
    }

    return 'Required objects verified';
  }

  DateTime _lastAlarm = DateTime.fromMillisecondsSinceEpoch(0);

  static const Duration _faceAnalysisInterval = Duration(milliseconds: 450);

  // Same safety grace used by Active verification.
  // Focus verification should react much faster than Active mode.
  static const Duration _objectInitialGrace = Duration(milliseconds: 2500);
  static const Duration _objectMissingGrace = Duration(milliseconds: 1000);

  // Focus requires a stronger visual match so random background regions
  // are less likely to be accepted as the saved object.
  // ===========================================================
  // INIT
  // ===========================================================

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _recheckFlashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );

    _remainingTime = ValueNotifier<Duration>(remainingLiveTime(widget.task));

    _thresholds = VerificationThresholds.fromSensitivity(
      widget.task.sensitivity,
      widget.task.focusActivity,
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _sessionTick();
    });

    if (widget.task.stayInPosition || widget.task.objectInFrame) {
      _initializeMl();
    } else {
      _cameraInitializing = false;
      _status = 'No verification rule selected.';
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _timer?.cancel();

    _recheckFlashController.dispose();

    _remainingTime.dispose();

    _disposeCamera();

    _poseDetector?.close();

    _faceDetector?.close();

    _objectLocator?.close();

    _objectRecognition.dispose();

    super.dispose();
  }

  // ===========================================================
  // APP LIFECYCLE
  // ===========================================================
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.task.stayInPosition && !widget.task.objectInFrame) {
      return;
    }

    // =========================================================
    // APP LEFT / BACKGROUNDED
    // =========================================================

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Leaving TaskProof normally is a verification
      // violation.
      //
      // But if the USER intentionally paused the session,
      // backgrounding the app should not create another
      // violation.
      if (!_userPaused && _hasBeenMonitoring && widget.task.startedAt != null) {
        _leftAppWhileMonitoring = true;
      }

      unawaited(_disposeCamera());

      return;
    }

    // =========================================================
    // APP RETURNED
    // =========================================================

    if (state == AppLifecycleState.resumed &&
        widget.task.status == TaskStatus.live) {
      // If the user explicitly paused TaskProof,
      // leave the camera off until they press Resume.
      if (_userPaused) {
        _leftAppWhileMonitoring = false;

        return;
      }

      unawaited(_initializeCamera());

      if (_leftAppWhileMonitoring) {
        _leftAppWhileMonitoring = false;

        _forceWarning(
          'You left TaskProof during an active verification session.',
        );
      }
    }
  }

  // ===========================================================
  // INITIALIZE ML
  // ===========================================================

  Future<void> _initializeMl() async {
    if (!MlKitCameraImageConverter.supported) {
      if (!mounted) {
        return;
      }

      setState(() {
        _cameraInitializing = false;
        _status = 'Focus verification requires Android or iPhone.';
      });

      return;
    }

    // =========================================================
    // STAY IN POSITION
    // =========================================================

    if (widget.task.stayInPosition) {
      _poseDetector = PoseDetector(
        options: PoseDetectorOptions(
          model: PoseDetectionModel.base,
          mode: PoseDetectionMode.stream,
        ),
      );

      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
          enableTracking: true,
        ),
      );
    }

    // =========================================================
    // REQUIRED OBJECTS
    // =========================================================

    if (widget.task.objectInFrame && widget.task.requiredObjectIds.isNotEmpty) {
      _objectLocator = ObjectDetector(
        options: ObjectDetectorOptions(
          mode: DetectionMode.single,
          classifyObjects: false,
          multipleObjects: true,
        ),
      );
    }

    await _loadRequiredObjects();

    if (!mounted) {
      return;
    }

    await _initializeCamera();
  }

  Future<void> _loadRequiredObjects() async {
    if (!widget.task.objectInFrame) {
      _objectProfilesReady = true;
      return;
    }

    final ids = widget.task.requiredObjectIds;

    if (ids.isEmpty) {
      _objectProfilesReady = true;
      return;
    }

    try {
      final result = await _objectRecognition.loadRequiredObjects(ids);

      if (!mounted) {
        return;
      }

      final objectsById = {
        for (final object in result.objects) object.id: object,
      };

      _requiredObjects
        ..clear()
        ..addAll(
          ids.map((id) {
            final object = objectsById[id];

            return _FocusRequiredObjectState(
              id: id,
              name: object?.name ?? 'Saved object unavailable',
              available: object != null,
            );
          }),
        );

      _objectProfilesReady = true;
    } catch (error) {
      debugPrint('Focus object profile load error: $error');

      _requiredObjects
        ..clear()
        ..addAll(
          ids.map(
            (id) => _FocusRequiredObjectState(
              id: id,
              name: 'Saved object unavailable',
              available: false,
            ),
          ),
        );

      _objectProfilesReady = true;
    }
  }
  // ===========================================================
  // CAMERA
  // ===========================================================

  Future<void> _initializeCamera() async {
    // An intentionally paused Focus session must not
    // restart the camera until Resume is pressed.
    if (_userPaused || _startingCamera || _controller != null) {
      return;
    }

    _startingCamera = true;

    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _cameraInitializing = false;
            _status = 'No camera available.';
          });
        }

        return;
      }

      _camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        _camera!,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: MlKitCameraImageConverter.cameraFormat,
      );

      await controller.initialize();

      // The user could press Pause while the camera
      // was still initializing.
      if (!mounted || _userPaused) {
        await controller.dispose();
        return;
      }

      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {}

      _controller = controller;

      _latestFaces = const [];

      _lastFaceAnalysis = DateTime.fromMillisecondsSinceEpoch(0);

      await controller.startImageStream(_processFrame);

      if (!mounted || _userPaused) {
        await _disposeCamera();
        return;
      }

      setState(() {
        _cameraInitializing = false;

        if (widget.task.stayInPosition && widget.task.poseReference == null) {
          _status = 'Get into your normal position, then calibrate.';
        } else {
          widget.task.startedAt ??= DateTime.now();

          _remainingTime.value = remainingLiveTime(widget.task);

          _objectMonitoringStartedAt ??= DateTime.now();

          _status = widget.task.objectInFrame
              ? _requiredObjectPrompt
              : 'Actively verifying';

          _hasBeenMonitoring = true;
        }
      });
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _cameraInitializing = false;

        _status = 'Camera error: ${error.description ?? error.code}';
      });
    } finally {
      _startingCamera = false;
    }
  }

  Future<void> _disposeCamera() async {
    _objectRecognition.resetTemporalState();

    _resetFidgetTracking();

    _latestPose = null;

    _latestFaces = const [];

    _lastAnalysis = DateTime.fromMillisecondsSinceEpoch(0);

    _lastFaceAnalysis = DateTime.fromMillisecondsSinceEpoch(0);

    // If calibration wasn't completed yet,
    // discard incomplete calibration samples.
    if (widget.task.poseReference == null) {
      _liveCalibrationSamples.clear();

      _liveCalibrationReady = false;
    }

    for (final object in _requiredObjects) {
      object.lastMatchedAt = null;
    }

    _objectMonitoringStartedAt = null;

    final controller = _controller;

    _controller = null;

    if (controller == null) {
      return;
    }

    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}

    try {
      await controller.dispose();
    } catch (_) {}
  }

  // ===========================================================
  // CAMERA FRAME PROCESSING
  // ===========================================================

  Future<void> _processFrame(CameraImage image) async {
    if (_userPaused || _processing || _controller == null || _camera == null) {
      return;
    }

    final controller = _controller!;
    final camera = _camera!;
    final now = DateTime.now();

    final poseDue =
        widget.task.stayInPosition &&
        now.difference(_lastAnalysis) >= const Duration(milliseconds: 180);

    final objectDue =
        widget.task.objectInFrame &&
        _objectProfilesReady &&
        _objectRecognition.isAnalysisDue;

    if (!poseDue && !objectDue) {
      return;
    }

    ObjectFrameSnapshot? objectSnapshot;

    // Copy the object frame BEFORE awaiting ML Kit.
    if (objectDue) {
      try {
        objectSnapshot = _objectRecognition.captureFrame(
          image,
          camera: camera,
          deviceOrientation: controller.value.deviceOrientation,
        );
      } catch (error) {
        debugPrint('Focus object frame capture error: $error');
      }
    }

    final frame = MlKitCameraImageConverter.convert(
      image: image,
      camera: camera,
      deviceOrientation: controller.value.deviceOrientation,
    );

    if (frame == null) {
      return;
    }

    _processing = true;

    try {
      var current = _latestPose;

      // =====================================================
      // BODY / POSITION
      // =====================================================

      if (poseDue) {
        _lastAnalysis = now;

        final poseDetector = _poseDetector;
        final faceDetector = _faceDetector;

        if (poseDetector != null && faceDetector != null) {
          final poses = await poseDetector.processImage(frame.inputImage);

          var faces = _latestFaces;

          final reference = widget.task.poseReference;

          final shouldTrackFace =
              reference == null || reference.faceTrackingEnabled;

          if (shouldTrackFace &&
              now.difference(_lastFaceAnalysis) >= _faceAnalysisInterval) {
            _lastFaceAnalysis = now;

            faces = await faceDetector.processImage(frame.inputImage);

            _latestFaces = faces;
          } else if (!shouldTrackFace) {
            faces = const [];
            _latestFaces = const [];
          }

          current = TaskPoseAnalyzer.createSnapshot(
            poses: poses,
            faces: faces,
            imageSize: frame.imageSize,
          );

          _latestPose = current;
        }
      }

      // =====================================================
      // REQUIRED OBJECTS
      // =====================================================

      if (objectDue && objectSnapshot != null) {
        final detectedBounds = <Rect>[];

        final locator = _objectLocator;

        if (locator != null) {
          try {
            final objects = await locator.processImage(frame.inputImage);

            detectedBounds.addAll(objects.map((object) => object.boundingBox));
          } catch (error) {
            debugPrint('Focus object localization error: $error');
          }
        }

        // =====================================================
        // FOCUS OBJECT VERIFICATION
        // =====================================================
        //
        // ML Kit localization is used when it can identify useful
        // object regions.
        //
        // However, small, flat, partially hidden, or unusual objects
        // such as a mouse may not always receive an ML Kit bounding
        // box.
        //
        // ObjectRecognitionService already contains its own
        // multi-scale fallback search. Therefore always run the
        // visual matcher.
        //
        // If detectedBounds is empty, the recognition service will
        // automatically search appropriate regions of the frame.
        // =====================================================

        final matches = await _objectRecognition.analyzeSnapshot(
          objectSnapshot,
          detectedBounds: detectedBounds,
        );

        final matchesById = {for (final match in matches) match.id: match};

        final checkedAt = DateTime.now();

        for (final object in _requiredObjects) {
          final match = matchesById[object.id];

          if (match == null) {
            continue;
          }

          final previousMatch = object.lastMatchedAt;

          final currentlyVerified =
              previousMatch != null &&
              checkedAt.difference(previousMatch) < _objectMissingGrace;

          final minimumConfidence = currentlyVerified
              ? _objectOngoingMatchConfidence
              : _objectInitialMatchConfidence;

          final strongMatch =
              match.isMatch &&
              !match.isTemporarilyMissing &&
              match.confidence >= minimumConfidence;

          debugPrint(
            'Focus object "${object.name}" '
            'confidence=${match.confidence.toStringAsFixed(3)} '
            'match=${match.isMatch} '
            'required=${minimumConfidence.toStringAsFixed(2)}',
          );

          if (strongMatch) {
            object.lastMatchedAt = checkedAt;
          }
        }
      }

      if (!mounted) {
        return;
      }

      // =====================================================
      // CALIBRATION
      // =====================================================

      if (widget.task.stayInPosition && widget.task.poseReference == null) {
        if (current == null) {
          _liveCalibrationSamples.clear();
          _liveCalibrationReady = false;

          const nextStatus =
              'Move into view so TaskProof can learn your focus position.';

          if (_status != nextStatus) {
            setState(() {
              _status = nextStatus;
            });
          }

          return;
        }

        _liveCalibrationSamples.add(current);

        // Roughly 1.4 seconds at the current ~180ms pose interval.
        if (_liveCalibrationSamples.length > 8) {
          _liveCalibrationSamples.removeAt(0);
        }

        final adaptiveReference = TaskPoseAnalyzer.buildAdaptiveReference(
          _liveCalibrationSamples,
        );

        final ready = adaptiveReference != null;

        if (_liveCalibrationReady != ready ||
            _status !=
                (ready
                    ? 'Focus area learned. Ready to start.'
                    : 'Learning your normal position...')) {
          setState(() {
            _liveCalibrationReady = ready;

            _status = ready
                ? 'Focus area learned. Ready to start.'
                : 'Learning your normal position...';
          });
        }

        return;
      }

      // This now evaluates BOTH enabled verification rules.
      _evaluatePosition(current);
    } catch (error) {
      debugPrint('Live verification processing error: $error');
    } finally {
      _processing = false;
    }
  }

  // ===========================================================
  // EVALUATE POSITION
  // ===========================================================
  void _evaluatePosition(PoseReference? current) {
    final reference = widget.task.poseReference;

    String? violation;

    if (widget.task.stayInPosition) {
      if (reference == null) {
        return;
      }

      if (current == null) {
        _resetFidgetTracking();

        violation = 'Your focus area is no longer clearly visible.';
      } else {
        final thresholds = _thresholds;

        final metrics = TaskPoseAnalyzer.compareToReference(
          reference: reference,
          current: current,
        );

        final distractingFidget = _updateFidgetTracking(reference, current);

        if (!metrics.hasEnoughCoverage) {
          violation = 'Not enough of your focus position is visible.';
        } else {
          double? yawDifference;
          double? pitchDifference;

          if (current.headYaw != null && reference.headYaw != null) {
            yawDifference = TaskPoseAnalyzer.angleDifference(
              current.headYaw!,
              reference.headYaw!,
            );
          }

          if (current.headPitch != null && reference.headPitch != null) {
            pitchDifference = TaskPoseAnalyzer.angleDifference(
              current.headPitch!,
              reference.headPitch!,
            );
          }

          // Face was reliably visible during calibration,
          // so losing it now contributes to distraction.
          if (reference.faceTrackingEnabled && !current.faceDetected) {
            violation = 'Look back toward your focus area.';
          }
          // Sustained looking away.
          else if ((yawDifference != null &&
                  yawDifference > thresholds.headYaw) ||
              (pitchDifference != null &&
                  pitchDifference > thresholds.headPitch)) {
            violation = 'Look back toward your focus area.';
          }
          // Left the general study/work area.
          else if (metrics.centerMovement > thresholds.bodyPosition ||
              metrics.scaleDifference > thresholds.bodyScale) {
            violation = 'Return to your focus area.';
          }
          // Large body orientation change:
          // sitting -> laying/reclining, etc.
          else if (metrics.bodyAxisDifference != null &&
              metrics.bodyAxisDifference! > thresholds.bodyAxisChange) {
            violation = 'Return to your normal working position.';
          }
          // Large structural change without demanding
          // exact Workout-style form.
          else if (metrics.structuralDeviation != null &&
              metrics.structuralDeviation! > thresholds.majorPoseChange) {
            violation = 'Your focus posture changed too much.';
          }
          // Long repetitive wrist movement.
          else if (distractingFidget) {
            violation = 'Settle your hands and return to your task.';
          }
        }
      }
    }

    if (violation == null && widget.task.objectInFrame) {
      violation = _objectViolation(DateTime.now());
    }

    if (violation == null) {
      _handleGoodPosition();
    } else {
      _handleViolation(violation);
    }
  }

  bool _updateFidgetTracking(PoseReference reference, PoseReference current) {
    final activity = widget.task.focusActivity;

    final handMotion = TaskPoseAnalyzer.handMotion(
      reference: reference,
      current: current,
      previous: _previousFocusPose,
    );

    _previousFocusPose = current;

    // Very cheap smoothing.
    _handMotionEma = (_handMotionEma * 0.78) + (handMotion * 0.22);

    // Do NOT try to distinguish pencil fidgeting from
    // actual writing/typing. The camera cannot do that
    // reliably enough.
    if (activity == FocusActivity.writingNotes ||
        activity == FocusActivity.computerWork ||
        handMotion == 0.0) {
      _fidgetStartedAt = null;
      return false;
    }

    if (_handMotionEma <= _thresholds.fidgetMotion) {
      _fidgetStartedAt = null;
      return false;
    }

    final now = DateTime.now();

    _fidgetStartedAt ??= now;

    return now.difference(_fidgetStartedAt!).inMilliseconds >=
        _thresholds.fidgetMilliseconds;
  }

  void _resetFidgetTracking() {
    _previousFocusPose = null;
    _handMotionEma = 0.0;
    _fidgetStartedAt = null;
  }

  String? _objectViolation(DateTime now) {
    if (!widget.task.objectInFrame) {
      return null;
    }

    if (!_objectProfilesReady) {
      return null;
    }

    if (widget.task.requiredObjectIds.isEmpty) {
      return 'No required object is configured.';
    }

    final monitoringStartedAt =
        _objectMonitoringStartedAt ?? widget.task.startedAt;

    if (monitoringStartedAt == null) {
      return null;
    }

    final missingObjects = _requiredObjects.where((object) {
      if (!object.available) {
        return now.difference(monitoringStartedAt) >= _objectInitialGrace;
      }

      final lastMatchedAt = object.lastMatchedAt;

      if (lastMatchedAt == null) {
        return now.difference(monitoringStartedAt) >= _objectInitialGrace;
      }

      return now.difference(lastMatchedAt) >= _objectMissingGrace;
    }).toList();

    if (missingObjects.isEmpty) {
      return null;
    }

    if (missingObjects.length == 1) {
      return '${missingObjects.first.name} is not detected.';
    }

    return '${missingObjects.length} required objects are not detected.';
  }

  // ===========================================================
  // VIOLATION
  // ===========================================================

  void _handleViolation(String reason) {
    final now = DateTime.now();

    final wasRechecking = _isRechecking;

    // If they were being checked again and move,
    // immediately return to the RED warning state.
    if (wasRechecking) {
      _stopRecheckFlash();
      _recoveryStartedAt = null;
    }

    // Already in warning mode.
    if (_warningActive && !_isRechecking) {
      final warningChanged = wasRechecking || _warningReason != reason;

      if (mounted && warningChanged) {
        setState(() {
          _warningReason = reason;
          _status = 'Focus interrupted';
        });
      } else {
        _warningReason = reason;
        _status = 'Focus interrupted';
      }

      _playWarning();
      return;
    }

    if (_warningReason != reason) {
      _warningReason = reason;
      _violationStartedAt = now;
    }

    _violationStartedAt ??= now;

    final violationDuration = now.difference(_violationStartedAt!);

    // Keep your existing grace period so tiny movements
    // don't instantly trigger the alarm.
    if (violationDuration <
        Duration(milliseconds: _thresholds.graceMilliseconds)) {
      _status = 'Checking focus...';

      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _warningActive = true;
      _recoveryStartedAt = null;
      _status = 'Focus interrupted';
    });

    _playWarning();
  }

  // ===========================================================
  // GOOD POSITION
  // ===========================================================

  void _handleGoodPosition() {
    final now = DateTime.now();

    _violationStartedAt = null;

    // Do NOT call the session verified until every
    // required object has actually been recognized.
    if (widget.task.objectInFrame && !_requiredObjectsVerifiedNow) {
      _warningReason = null;
      _status = _requiredObjectPrompt;

      return;
    }

    // Already verified.
    if (!_warningActive) {
      _warningReason = null;

      _status = widget.task.objectInFrame
          ? _requiredObjectVerifiedLabel
          : 'Actively verifying';

      return;
    }

    // They just returned after being out of position.
    // Begin flashing RED <-> WHITE.
    if (_recoveryStartedAt == null) {
      _recoveryStartedAt = now;

      _startRecheckFlash();

      if (mounted) {
        setState(() {
          _status = 'Verifying again...';
        });
      }

      return;
    }

    // They must remain correctly positioned for 1.4 seconds.
    if (now.difference(_recoveryStartedAt!) <
        const Duration(milliseconds: 1400)) {
      return;
    }

    // They passed re-verification.
    _stopRecheckFlash();

    if (!mounted) {
      return;
    }

    setState(() {
      _warningActive = false;
      _warningReason = null;
      _recoveryStartedAt = null;
      _status = 'Actively verifying';
    });
  }

  void _startRecheckFlash() {
    if (!_recheckFlashController.isAnimating) {
      _recheckFlashController.repeat(reverse: true);
    }
  }

  void _stopRecheckFlash() {
    if (_recheckFlashController.isAnimating) {
      _recheckFlashController.stop();
    }

    _recheckFlashController.value = 0;
  }

  // ===========================================================
  // FORCE WARNING
  // ===========================================================

  void _forceWarning(String reason) {
    _stopRecheckFlash();

    _recoveryStartedAt = null;

    _warningReason = reason;

    _warningActive = true;

    _violationStartedAt = DateTime.now();

    if (mounted) {
      setState(() {
        _status = 'Focus interrupted';
      });
    }

    _playWarning();
  }

  // ===========================================================
  // WARNING SOUND / VIBRATION
  // ===========================================================

  Future<void> _playWarning() async {
    // They've returned to position.
    // We're checking them again, so stop sounding the alarm.
    if (_isRechecking) {
      return;
    }

    final now = DateTime.now();

    // Repeat roughly once per second.
    if (now.difference(_lastAlarm) < const Duration(milliseconds: 900)) {
      return;
    }

    _lastAlarm = now;

    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}

    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  // ===========================================================
  // CALIBRATE
  // ===========================================================

  void _calibrateAndStart() {
    final reference = TaskPoseAnalyzer.buildAdaptiveReference(
      _liveCalibrationSamples,
    );

    if (reference == null) {
      return;
    }

    _resetFidgetTracking();

    setState(() {
      widget.task.poseReference = reference;

      widget.task.startedAt = DateTime.now();

      _objectMonitoringStartedAt ??= DateTime.now();

      _remainingTime.value = widget.task.duration;

      _warningActive = false;

      _warningReason = null;

      _violationStartedAt = null;

      _recoveryStartedAt = null;

      _status = 'Actively verifying';

      _hasBeenMonitoring = true;

      _liveCalibrationReady = false;
    });

    _liveCalibrationSamples.clear();
  }

  // ===========================================================
  // SESSION TIMER
  // ===========================================================
  // ===========================================================
  // PAUSE / RESUME
  // ===========================================================

  Future<void> _togglePause() async {
    if (_pauseTransitionRunning ||
        widget.task.status != TaskStatus.live ||
        widget.task.startedAt == null) {
      return;
    }

    _pauseTransitionRunning = true;

    // =========================================================
    // PAUSE
    // =========================================================

    if (!_userPaused) {
      final remaining = remainingLiveTime(widget.task);

      // The session finished at essentially the same
      // moment Pause was pressed.
      if (remaining <= Duration.zero) {
        _pauseTransitionRunning = false;

        await _completeSession();

        return;
      }

      if (!mounted) {
        _pauseTransitionRunning = false;

        return;
      }

      setState(() {
        _userPaused = true;

        _pausedRemaining = remaining;

        // Freeze the visible timer immediately.
        _remainingTime.value = remaining;

        // Pause is intentional, so clear verification
        // warnings and incomplete violation timers.
        _warningActive = false;

        _warningReason = null;

        _violationStartedAt = null;

        _recoveryStartedAt = null;

        _leftAppWhileMonitoring = false;

        // Once the camera has been disposed,
        // _liveCameraBody() will display this status.
        _cameraInitializing = false;

        _status = 'Paused';
      });

      // Camera + verification stop while paused.
      await _disposeCamera();

      if (!mounted) {
        _pauseTransitionRunning = false;

        return;
      }

      setState(() {
        _pauseTransitionRunning = false;
      });

      return;
    }

    // =========================================================
    // RESUME
    // =========================================================

    final remaining = _pausedRemaining ?? _remainingTime.value;

    if (!mounted) {
      _pauseTransitionRunning = false;

      return;
    }

    setState(() {
      // Rebuild startedAt so time spent paused is NOT
      // counted as session time.
      //
      // Example:
      //
      // 30 minute task
      // 20 minutes remaining
      //
      // elapsed task time = 10 minutes.
      //
      // We move startedAt to "10 minutes ago" regardless
      // of how long the user stayed paused.
      final elapsedTaskTime = widget.task.duration - remaining;

      widget.task.startedAt = DateTime.now().subtract(elapsedTaskTime);

      _userPaused = false;

      _pausedRemaining = null;

      _cameraInitializing = true;

      _status = 'Resuming verification...';
    });

    await _initializeCamera();

    if (!mounted) {
      _pauseTransitionRunning = false;

      return;
    }

    setState(() {
      _pauseTransitionRunning = false;
    });
  }

  void _sessionTick() {
    if (!mounted) {
      return;
    }

    if (widget.task.status == TaskStatus.completed) {
      return;
    }

    if (widget.task.status != TaskStatus.live) {
      return;
    }

    // =========================================================
    // PAUSED
    // =========================================================

    if (_userPaused) {
      final remaining = _pausedRemaining;

      // Keep the displayed countdown frozen at the
      // exact value it had when Pause was pressed.
      if (remaining != null && (ModalRoute.of(context)?.isCurrent ?? true)) {
        _remainingTime.value = remaining;
      }

      return;
    }

    // =========================================================
    // RUNNING
    // =========================================================

    if (widget.task.startedAt == null) {
      return;
    }

    final remaining = remainingLiveTime(widget.task);

    if (remaining <= Duration.zero) {
      unawaited(_completeSession());

      return;
    }

    // Continue repeating the warning while an
    // unresolved verification violation exists.
    if (_warningActive && !_isRechecking) {
      _playWarning();
    }

    // Only the countdown needs to update every second.
    if (ModalRoute.of(context)?.isCurrent ?? true) {
      _remainingTime.value = remaining;
    }
  }
  // ===========================================================
  // COMPLETE
  // ===========================================================

  Future<void> _completeSession() async {
    if (widget.task.status == TaskStatus.completed) {
      return;
    }

    widget.task.status = TaskStatus.completed;

    widget.task.completedAt = DateTime.now();

    widget.task.startedAt = null;

    _warningActive = false;

    _timer?.cancel();

    await _disposeCamera();

    if (!mounted) {
      return;
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Task Completed'),
        content: Text('${widget.task.name} has been completed.'),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _C.red),
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );

    if (!mounted) {
      return;
    }

    Navigator.pop(context);
  }

  // ===========================================================
  // END EARLY
  // ===========================================================

Future<void> _confirmEndEarly() async {
  final end = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 34),
        child: Container(
          width: 360,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Warning icon
              Container(
                width: 58,
                height: 58,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFE8EA),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: _C.red,
                    size: 30,
                  ),
                ),
              ),

              const SizedBox(height: 18),

              const Text(
                'End session?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF17181C),
                  fontSize: 22,
                  fontFamily: 'Nunito Sans',
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),

              const SizedBox(height: 9),

              const Text(
                'The task will not be marked as completed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF737782),
                  fontSize: 14,
                  fontFamily: 'Nunito Sans',
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),

              const SizedBox(height: 24),

              const Divider(
                height: 1,
                thickness: 1,
                color: Color(0xFFECEDEF),
              ),

              const SizedBox(height: 18),

              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(dialogContext, false);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF17181C),
                          side: const BorderSide(
                            color: Color(0xFFDADCE1),
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 14,
                            fontFamily: 'Nunito Sans',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(dialogContext, true);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: _C.red,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'End Session',
                          style: TextStyle(
                            fontSize: 14,
                            fontFamily: 'Nunito Sans',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  if (end != true || !mounted) {
    return;
  }

  widget.task.status = TaskStatus.ready;
  widget.task.startedAt = null;
  widget.task.completedAt = null;
  _warningActive = false;

  await _disposeCamera();

  if (!mounted) {
    return;
  }

  Navigator.pop(context);
}

  Color _verificationColor(bool needsCalibration) {
    if (_userPaused) {
      return const Color(0xFF9CA3AF);
    }

    if (needsCalibration) {
      return const Color(0xFFFFB72E);
    }

    // Flash from red to white while verifying again.
    if (_isRechecking) {
      return Color.lerp(_C.red, Colors.white, _recheckFlashController.value) ??
          _C.red;
    }

    if (_warningActive && !_isRechecking) {
      return _C.red;
    }

    // Required object has NOT actually been
    // confirmed yet. Never show green here.
    if (widget.task.objectInFrame && !_requiredObjectsVerifiedNow) {
      return const Color(0xFFFFB72E);
    }

    return _verifiedGreen;
  }

  String _verificationLabel(bool needsCalibration) {
    if (_userPaused) {
      return 'Paused';
    }

    if (needsCalibration) {
      return 'Ready to calibrate';
    }

    if (_isRechecking) {
      return 'Verifying again...';
    }

    if (_warningActive && !_isRechecking) {
      return 'Focus interrupted';
    }

    if (widget.task.objectInFrame && !_requiredObjectsVerifiedNow) {
      return _requiredObjectPrompt;
    }

    if (widget.task.objectInFrame) {
      return _requiredObjectVerifiedLabel;
    }

    return 'Actively Verifying';
  }

  Widget _buildVerificationStatus(bool needsCalibration) {
    return AnimatedBuilder(
      animation: _recheckFlashController,
      builder: (context, _) {
        final verificationColor = _verificationColor(needsCalibration);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: widget.isDarkMode
                ? const Color(0xFF0E1116)
                : const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: widget.isDarkMode
                  ? const Color(0xFF2A2F37)
                  : const Color(0xFFE0E3E8),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: verificationColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 9),
              Text(
                _verificationLabel(needsCalibration),
                style: TextStyle(
                  color: verificationColor,
                  fontSize: 14,
                  fontFamily: 'Nunito Sans',
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================
  // BUILD LIVE PAGE
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    final task = widget.task;

    final needsCalibration = task.stayInPosition && task.poseReference == null;

    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async {
        await _confirmEndEarly();
        return false;
      },
      child: Scaffold(
        backgroundColor: widget.isDarkMode
            ? const Color(0xFF07090D)
            : const Color(0xFFF8F8F9),
        body: SafeArea(
          child: Column(
            children: [
              // =================================================
              // HEADER
              // =================================================
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _confirmEndEarly,
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: widget.isDarkMode ? Colors.white : Colors.black,
                        size: 26,
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          task.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: widget.isDarkMode
                                ? Colors.white
                                : const Color(0xFF111318),
                            fontSize: 38,
                            height: 1.05,
                            fontFamily: 'Nunito Sans',
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // =================================================
              // CAMERA AREA
              // =================================================
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _liveCameraBody(),

                        if (task.stayInPosition)
                          IgnorePointer(
                            child: RepaintBoundary(
                              child: AnimatedBuilder(
                                animation: _recheckFlashController,
                                builder: (context, _) {
                                  return CustomPaint(
                                    painter: _LiveCameraPainter(
                                      color: _verificationColor(
                                        needsCalibration,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),

                        // =========================================
                        // WARNING RED OVERLAY
                        // =========================================
                        if (_warningActive && !_isRechecking)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Container(
                                color: _C.red.withValues(alpha: .15),
                              ),
                            ),
                          ),

                        // =========================================
                        // WARNING MESSAGE
                        // =========================================
                        if (_warningActive && !_isRechecking)
                          Center(
                            child: Container(
                              margin: const EdgeInsets.all(24),
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                18,
                                20,
                                18,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xEB160B0D),
                                border: Border.all(color: _C.red, width: 2),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: _C.red,
                                    size: 45,
                                  ),
                                  const SizedBox(height: 9),
                                  const Text(
                                    'Focus Interrupted',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 21,
                                      fontFamily: 'Nunito Sans',
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _warningReason ??
                                        'Return your attention to your task',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFFE3E5E8),
                                      fontSize: 14,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // =========================================
                        // TOP STATUS
                        // =========================================
                        Positioned(
                          top: 16,
                          left: 16,
                          child: _buildVerificationStatus(needsCalibration),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // =================================================
              // BOTTOM CONTROLS
              // =================================================
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                child: Column(
                  children: [
                    if (needsCalibration)
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: !_liveCalibrationReady
                              ? null
                              : _calibrateAndStart,
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: _C.red,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFF454950),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Set This Position & Start',
                            style: TextStyle(
                              fontSize: 16,
                              fontFamily: 'Nunito Sans',
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      )
                    else ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: widget.isDarkMode
                              ? const Color(0xFF0E1116)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: widget.isDarkMode
                                ? const Color(0xFF252A31)
                                : const Color(0xFFE1E3E7),
                          ),
                        ),
                        child: Row(
                          children: [
                            // PAUSE / RESUME
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: _pauseTransitionRunning
                                      ? null
                                      : () {
                                          unawaited(_togglePause());
                                        },
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 160),
                                    opacity: _pauseTransitionRunning ? .55 : 1,
                                    child: Container(
                                      width: 54,
                                      height: 54,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: widget.isDarkMode
                                            ? const Color(0xFF191D23)
                                            : const Color(0xFFF5F5F6),
                                        border: Border.all(
                                          color: _userPaused
                                              ? _verifiedGreen
                                              : const Color(0xFFD7D9DE),
                                        ),
                                      ),
                                      child: _pauseTransitionRunning
                                          ? const Padding(
                                              padding: EdgeInsets.all(16),
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.2,
                                                color: _C.red,
                                              ),
                                            )
                                          : Icon(
                                              _userPaused
                                                  ? Icons.play_arrow_rounded
                                                  : Icons.pause_rounded,
                                              color: _userPaused
                                                  ? _verifiedGreen
                                                  : widget.isDarkMode
                                                  ? Colors.white
                                                  : Colors.black,
                                            ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 5),

                                Text(
                                  _userPaused ? 'Resume' : 'Pause',
                                  style: TextStyle(
                                    color: widget.isDarkMode
                                        ? Colors.white
                                        : Colors.black,
                                    fontSize: 12,
                                    fontFamily: 'Nunito Sans',
                                    fontWeight: _userPaused
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),

                            // TIMER
                            Expanded(
                              child: Column(
                                children: [
                                  Text(
                                    'Time Remaining',
                                    style: TextStyle(
                                      color: widget.isDarkMode
                                          ? Colors.white
                                          : Colors.black,
                                      fontSize: 17,
                                      fontFamily: 'Nunito Sans',
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  ValueListenableBuilder<Duration>(
                                    valueListenable: _remainingTime,
                                    builder: (context, remaining, _) {
                                      return Text(
                                        formatLiveCountdown(remaining),
                                        style: const TextStyle(
                                          color: _C.red,
                                          fontSize: 38,
                                          fontFamily: 'Nunito Sans',
                                          fontWeight: FontWeight.w900,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),

                            // END SESSION
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: _confirmEndEarly,
                                  child: Container(
                                    width: 54,
                                    height: 54,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: widget.isDarkMode
                                          ? const Color(0xFF191D23)
                                          : const Color(0xFFF5F5F6),
                                      border: Border.all(
                                        color: _C.red,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.stop_rounded,
                                      color: _C.red,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  'End Session',
                                  style: TextStyle(
                                    color: widget.isDarkMode
                                        ? Colors.white
                                        : Colors.black,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================
  // CAMERA BODY
  // ===========================================================

  Widget _liveCameraBody() {
    if (_cameraInitializing) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: _C.red)),
      );
    }

    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Text(
              _status,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      );
    }

    return CameraPreview(controller);
  }
}

class _FocusRequiredObjectState {
  _FocusRequiredObjectState({
    required this.id,
    required this.name,
    required this.available,
  });

  final String id;
  final String name;
  final bool available;

  DateTime? lastMatchedAt;
}

// =============================================================
// VERIFICATION THRESHOLDS
// =============================================================

class VerificationThresholds {
  const VerificationThresholds({
    required this.bodyPosition,
    required this.bodyScale,
    required this.headYaw,
    required this.headPitch,
    required this.headRoll,
    required this.majorPoseChange,
    required this.bodyAxisChange,
    required this.fidgetMotion,
    required this.fidgetMilliseconds,
    required this.graceMilliseconds,
  });

  final double bodyPosition;
  final double bodyScale;

  final double headYaw;
  final double headPitch;
  final double headRoll;

  final double majorPoseChange;
  final double bodyAxisChange;

  final double fidgetMotion;
  final int fidgetMilliseconds;

  final int graceMilliseconds;

  static VerificationThresholds fromSensitivity(
    double sensitivity,
    FocusActivity activity,
  ) {
    final t = sensitivity.clamp(0.0, 1.0);

    var yawLow = 44.0;
    var yawHigh = 20.0;

    var pitchLow = 36.0;
    var pitchHigh = 18.0;

    var poseLow = 0.80;
    var poseHigh = 0.56;

    var axisLow = 52.0;
    var axisHigh = 32.0;

    var fidgetLow = 0.24;
    var fidgetHigh = 0.15;

    var fidgetMsLow = 6500.0;
    var fidgetMsHigh = 4000.0;

    switch (activity) {
      case FocusActivity.general:
        break;

      case FocusActivity.reading:
        // Looking downward/page movement is normal.
        pitchLow = 54;
        pitchHigh = 32;

        poseLow = 0.86;
        poseHigh = 0.62;

        fidgetLow = 0.27;
        fidgetHigh = 0.18;

        fidgetMsLow = 7000;
        fidgetMsHigh = 4500;

        break;

      case FocusActivity.writingNotes:
        // Hand motion/downward head angle expected.
        yawLow = 48;
        yawHigh = 24;

        pitchLow = 58;
        pitchHigh = 36;

        poseLow = 0.92;
        poseHigh = 0.68;

        axisLow = 58;
        axisHigh = 38;

        break;

      case FocusActivity.computerWork:
        yawLow = 40;
        yawHigh = 18;

        pitchLow = 34;
        pitchHigh = 16;

        poseLow = 0.86;
        poseHigh = 0.60;

        break;
    }

    return VerificationThresholds(
      bodyPosition: _lerp(0.20, 0.13, t),

      bodyScale: _lerp(0.50, 0.36, t),

      headYaw: _lerp(yawLow, yawHigh, t),

      headPitch: _lerp(pitchLow, pitchHigh, t),

      headRoll: 180,

      majorPoseChange: _lerp(poseLow, poseHigh, t),

      bodyAxisChange: _lerp(axisLow, axisHigh, t),

      fidgetMotion: _lerp(fidgetLow, fidgetHigh, t),

      fidgetMilliseconds: _lerp(fidgetMsLow, fidgetMsHigh, t).round(),

      graceMilliseconds: _lerp(1500, 650, t).round(),
    );
  }

  static double _lerp(double start, double end, double t) {
    return start + ((end - start) * t);
  }
}
// =============================================================
// LIVE CAMERA PAINTER
// =============================================================

class _LiveCameraPainter extends CustomPainter {
  const _LiveCameraPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const inset = 24.0;

    const length = 36.0;

    final left = inset;

    final top = inset;

    final right = size.width - inset;

    final bottom = size.height - inset;

    canvas.drawLine(Offset(left, top), Offset(left + length, top), paint);

    canvas.drawLine(Offset(left, top), Offset(left, top + length), paint);

    canvas.drawLine(Offset(right, top), Offset(right - length, top), paint);

    canvas.drawLine(Offset(right, top), Offset(right, top + length), paint);

    canvas.drawLine(Offset(left, bottom), Offset(left + length, bottom), paint);

    canvas.drawLine(Offset(left, bottom), Offset(left, bottom - length), paint);

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
  bool shouldRepaint(covariant _LiveCameraPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

// =============================================================
// GLOBAL TIME HELPERS
// =============================================================

Duration remainingLiveTime(TaskData task) {
  final started = task.startedAt;

  if (started == null) {
    return task.duration;
  }

  final remaining = task.duration - DateTime.now().difference(started);

  if (remaining.isNegative) {
    return Duration.zero;
  }

  return remaining;
}

String formatCountdown(Duration duration) {
  var total = duration.inSeconds;

  if (total < 0) {
    total = 0;
  }

  final hours = total ~/ 3600;

  final minutes = (total % 3600) ~/ 60;

  final seconds = total % 60;

  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

String formatTaskDuration(Duration duration) {
  final hours = duration.inHours;

  final minutes = duration.inMinutes.remainder(60);

  final seconds = duration.inSeconds.remainder(60);

  if (hours > 0) {
    return '${hours}h ${minutes}m';
  }

  if (minutes > 0) {
    return '${minutes}m ${seconds}s';
  }

  return '${seconds}s';
}

String formatScheduled(DateTime date) {
  final now = DateTime.now();

  String day;

  if (DateUtils.isSameDay(date, now)) {
    day = 'Today';
  } else if (DateUtils.isSameDay(date, now.add(const Duration(days: 1)))) {
    day = 'Tomorrow';
  } else {
    day = '${date.month}/${date.day}/${date.year}';
  }

  return '$day, ${formatClock(date)}';
}

String formatClock(DateTime date) {
  var hour = date.hour;

  final suffix = hour >= 12 ? 'PM' : 'AM';

  hour %= 12;

  if (hour == 0) {
    hour = 12;
  }

  return '$hour:${date.minute.toString().padLeft(2, '0')} $suffix';
}

// =============================================================
// SMALL UI
// =============================================================

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.color = const Color(0xFF747987)});

  final String text;

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 13,
        fontFamily: 'Nunito Sans',
        fontWeight: FontWeight.w800,
        letterSpacing: .3,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    required this.background,
    required this.foreground,
  });

  final String text;

  final Color background;

  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontFamily: 'Nunito Sans',
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PulseDot extends StatelessWidget {
  const _PulseDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: const BoxDecoration(color: _C.red, shape: BoxShape.circle),
    );
  }
}

// =============================================================
// DRAWER
// =============================================================

class _AppDrawer extends StatelessWidget {
  const _AppDrawer();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _C.red,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TaskProof',
                          style: TextStyle(
                            fontSize: 20,
                            fontFamily: 'Nunito Sans',
                            fontWeight: FontWeight.w800,
                          ),
                        ),

                        Text(
                          user?.email ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _C.grey, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(),

            ListTile(
              leading: const Icon(Icons.task_alt_rounded),
              title: const Text('My Tasks'),
              onTap: () {
                Navigator.pop(context);
              },
            ),

            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('History'),
              onTap: () {},
            ),

            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {},
            ),

            const Spacer(),

            const Divider(),

            ListTile(
              leading: const Icon(Icons.logout_rounded, color: _C.red),
              title: const Text('Log out', style: TextStyle(color: _C.red)),
              onTap: () async {
                Navigator.pop(context);

                await FirebaseAuth.instance.signOut();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// FAB PAINTER
// =============================================================

class _ApertureButtonPainter extends CustomPainter {
  const _ApertureButtonPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final center = Offset(size.width / 2, size.height / 2);

    final plusOpacity = (1 - progress / .4).clamp(0.0, 1.0);

    final bracketProgress = ((progress - .2) / .55).clamp(0.0, 1.0);

    final checkOpacity = ((progress - .7) / .3).clamp(0.0, 1.0);

    if (plusOpacity > 0) {
      paint.color = Colors.white.withValues(alpha: plusOpacity);

      canvas.drawLine(
        Offset(center.dx - 12, center.dy),
        Offset(center.dx + 12, center.dy),
        paint,
      );

      canvas.drawLine(
        Offset(center.dx, center.dy - 12),
        Offset(center.dx, center.dy + 12),
        paint,
      );
    }

    if (bracketProgress > 0) {
      paint.color = Colors.white;

      const gap = 14.0;
      const length = 8.5;

      void bracket(double dx, double dy) {
        final target = Offset(center.dx + dx * gap, center.dy + dy * gap);

        final origin = Offset.lerp(center, target, bracketProgress)!;

        final currentLength = length * bracketProgress;

        canvas.drawLine(
          origin,
          origin.translate(-dx * currentLength, 0),
          paint,
        );

        canvas.drawLine(
          origin,
          origin.translate(0, -dy * currentLength),
          paint,
        );
      }

      bracket(-1, -1);
      bracket(1, -1);
      bracket(-1, 1);
      bracket(1, 1);
    }

    if (checkOpacity > 0) {
      paint.color = Colors.white.withValues(alpha: checkOpacity);

      final path = Path()
        ..moveTo(center.dx - 7, center.dy + 2.5)
        ..lineTo(center.dx - 1.5, center.dy + 7.5)
        ..lineTo(center.dx + 9.5, center.dy - 4.5);

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ApertureButtonPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

// =============================================================
// COLORS
// =============================================================

class _C {
  static const red = Color(0xFFFF101C);

  static const dark = Color(0xFF15171D);

  static const grey = Color(0xFF858995);
}

String formatLiveCountdown(Duration duration) {
  var total = duration.inSeconds;

  if (total < 0) {
    total = 0;
  }

  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;

  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}
