import 'package:flutter/material.dart';

// =============================================================
// TASK ICON TYPES
// =============================================================

enum TaskIconType {
  generic,
  study,
  cleaning,
  workout,
  running,
  computer,
  cooking,
  laundry,
  meditation,
  garden,
  sleep,
  shopping,
  hydration,
  health,
  music,
  phone,
  pet,
  selfCare,
}

// =============================================================
// TASK STATUS
// =============================================================

enum TaskStatus {
  ready,
  scheduled,
  live,
  completed,
}

// =============================================================
// TASK DATA
// =============================================================

class TaskData {
  TaskData({
    required this.id,
    required this.name,
    required this.icon,
    required this.hours,
    required this.minutes,
    required this.seconds,
    required this.stayInPosition,
    required this.objectInFrame,
    required this.alarm,
    required this.sensitivity,
    this.status = TaskStatus.ready,
    this.scheduledFor,
    this.startedAt,
    this.completedAt,
    this.scheduleAlertShown = false,
  });

  final String id;
  final String name;
  final TaskIconType icon;

  final int hours;
  final int minutes;
  final int seconds;

  final bool stayInPosition;
  final bool objectInFrame;

  final String alarm;
  final double sensitivity;

  TaskStatus status;

  DateTime? scheduledFor;
  DateTime? startedAt;
  DateTime? completedAt;

  bool scheduleAlertShown;

  Duration get duration {
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
    );
  }
}

// =============================================================
// NEW TASK PAGE
// =============================================================

class NewTaskPage extends StatefulWidget {
  const NewTaskPage({
    super.key,
    this.isDarkMode = false,
  });

  final bool isDarkMode;

  @override
  State<NewTaskPage> createState() => _NewTaskPageState();
}

class _NewTaskPageState extends State<NewTaskPage> {
  // ===========================================================
  // TASK NAME
  // ===========================================================

  final TextEditingController taskNameController =
      TextEditingController();

  // ===========================================================
  // DURATION
  // ===========================================================

  late final FixedExtentScrollController _hoursController;
  late final FixedExtentScrollController _minutesController;
  late final FixedExtentScrollController _secondsController;

  int hours = 4;
  int minutes = 30;
  int seconds = 0;

  // ===========================================================
  // SCHEDULE
  // ===========================================================

  bool scheduleEnabled = false;

  DateTime? selectedScheduleDate;
  TimeOfDay? selectedScheduleTime;

  // ===========================================================
  // VERIFICATION
  // ===========================================================

  bool stayInPosition = true;
  bool objectInFrame = false;

  // ===========================================================
  // REFERENCE SETUP
  // ===========================================================

  int capturedObjects = 0;
  bool referencePositionCaptured = false;

  // ===========================================================
  // OTHER SETTINGS
  // ===========================================================

  double sensitivity = 0.5;

  String selectedAlarm = 'Default Alarm';

  // ===========================================================
  // TASK ICON
  // ===========================================================

  TaskIconType selectedTaskIcon = TaskIconType.generic;

  bool taskIconManuallySelected = false;

  // ===========================================================
  // PRO
  // ===========================================================

  final bool isPro = false;

  // ===========================================================
  // INIT
  // ===========================================================

  @override
  void initState() {
    super.initState();

    _hoursController = FixedExtentScrollController(
      initialItem: hours,
    );

    _minutesController = FixedExtentScrollController(
      initialItem: minutes,
    );

    _secondsController = FixedExtentScrollController(
      initialItem: seconds,
    );
  }

  @override
  void dispose() {
    taskNameController.dispose();

    _hoursController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();

    super.dispose();
  }

  // ===========================================================
  // BUILD
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    final dark = widget.isDarkMode;

    final theme = Theme.of(context).copyWith(
      brightness:
          dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor:
          dark ? _T.background : const Color(0xFFF4F4F6),
      canvasColor:
          dark ? _T.surface : Colors.white,
      cardColor:
          dark ? _T.surface : Colors.white,
      dividerColor:
          dark ? _T.border : const Color(0xFFE2E3E7),
      colorScheme: dark
          ? const ColorScheme.dark(
              primary: _C.red,
              surface: _T.surface,
              onSurface: _T.text,
            )
          : const ColorScheme.light(
              primary: _C.red,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
    );

    return Theme(
      data: theme,
      child: Scaffold(
      backgroundColor:
          dark ? _T.background : const Color(0xFFF4F4F6),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 460,
          ),
          child: ColoredBox(
            color: dark ? _T.background : Colors.white,
            child: SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  18,
                  12,
                  18,
                  28,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // =================================================
                    // HEADER
                    // =================================================

                    _buildHeader(),

                    const SizedBox(height: 24),

                    // =================================================
                    // TASK NAME
                    // =================================================

                    const _SectionTitle(
                      'Task Name',
                    ),

                    const SizedBox(height: 9),

                    _buildTaskNameField(),

                    const SizedBox(height: 22),

                    // =================================================
                    // DURATION
                    // =================================================

                    const _SectionTitle(
                      'Duration',
                    ),

                    const SizedBox(height: 10),

                    _buildDurationPicker(),

                    const SizedBox(height: 8),

                    const Center(
                      child: Text(
                        'Max duration is 24 hours.',
                        style: TextStyle(
                          color: Color(0xFF676A74),
                          fontSize: 13,
                        ),
                      ),
                    ),

                    const _SectionDivider(),

                    // =================================================
                    // SCHEDULE
                    // =================================================

                    _buildScheduleSection(),

                    const _SectionDivider(),

                    // =================================================
                    // VERIFICATION RULES
                    // =================================================

                    const _SectionTitle(
                      'Verification Rules',
                    ),

                    const SizedBox(height: 10),

                    _buildVerificationRules(),

                    const _SectionDivider(),

                    // =================================================
                    // REFERENCE SETUP
                    // =================================================

                    const _SectionTitle(
                      'Reference Setup',
                    ),

                    const SizedBox(height: 3),

                    Text(
                      _referenceDescription,
                      style: TextStyle(
                        color: dark
                            ? _T.muted
                            : const Color(0xFF555861),
                        fontSize: 13,
                      ),
                    ),

                    const SizedBox(height: 10),

                    _buildReferenceSetup(),

                    const _SectionDivider(),

                    // =================================================
                    // ALARM
                    // =================================================

                    const _SectionTitle(
                      'Alarm Sound',
                    ),

                    const SizedBox(height: 9),

                    _buildAlarmSound(),

                    const SizedBox(height: 20),

                    // =================================================
                    // SENSITIVITY
                    // =================================================

                    const _SectionTitle(
                      'Sensitivity',
                    ),

                    const SizedBox(height: 8),

                    _buildSensitivity(),

                    const SizedBox(height: 22),

                    // =================================================
                    // SAVE TASK
                    // =================================================

                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: ElevatedButton(
                        onPressed: _saveTask,
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: _C.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              14,
                            ),
                          ),
                        ),
                        child: const Text(
                          'Save Task',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
    return Row(
      children: [
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: 42,
            minHeight: 42,
          ),
          onPressed: () {
            Navigator.pop(context);
          },
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 25,
            color: widget.isDarkMode
                ? _T.text
                : Colors.black,
          ),
        ),

        const SizedBox(width: 4),

        Text(
          'New Task',
          style: TextStyle(
            color: widget.isDarkMode
                ? _T.text
                : Colors.black,
            fontSize: 34,
            height: 1,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
          ),
        ),
      ],
    );
  }

  // ===========================================================
  // TASK NAME
  // ===========================================================

  Widget _buildTaskNameField() {
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: widget.isDarkMode
            ? _T.surface
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.isDarkMode
              ? _T.border
              : const Color(0xFFCDD0D7),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _showTaskIconPicker,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                9,
                7,
                6,
                7,
              ),
              child: Row(
                children: [
                  _TaskIconTile(
                    type: selectedTaskIcon,
                    size: 50,
                  ),

                  const SizedBox(width: 2),

                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: widget.isDarkMode
                        ? _T.muted
                        : const Color(0xFF30323A),
                    size: 21,
                  ),
                ],
              ),
            ),
          ),

          Container(
            width: 1,
            height: 40,
            color: widget.isDarkMode
                ? _T.border
                : const Color(0xFFE1E2E6),
          ),

          Expanded(
            child: TextField(
              controller: taskNameController,
              onChanged: _onTaskNameChanged,
              textInputAction: TextInputAction.next,
              style: TextStyle(
                color: widget.isDarkMode
                    ? _T.text
                    : Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: 'e.g. Study Session.',
                hintStyle: TextStyle(
                  color: widget.isDarkMode
                      ? _T.muted
                      : const Color(0xFF8D9099),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================
  // SMART ICON
  // ===========================================================

  void _onTaskNameChanged(
    String value,
  ) {
    if (taskIconManuallySelected) {
      return;
    }

    final suggestion = _getSuggestedTaskIcon(
      value,
    );

    if (suggestion != selectedTaskIcon) {
      setState(() {
        selectedTaskIcon = suggestion;
      });
    }
  }

  TaskIconType _getSuggestedTaskIcon(
    String taskName,
  ) {
    final text = taskName.toLowerCase().trim();

    if (text.isEmpty) {
      return TaskIconType.generic;
    }

    if (_containsAny(
      text,
      [
        'study',
        'studying',
        'read',
        'reading',
        'book',
        'books',
        'homework',
        'assignment',
        'school',
        'class',
        'lecture',
        'revision',
        'revise',
        'exam',
        'quiz',
        'test',
        'learn',
        'learning',
        'notes',
        'research',
        'essay',
      ],
    )) {
      return TaskIconType.study;
    }

    if (_containsAny(
      text,
      [
        'sweep',
        'sweeping',
        'clean',
        'cleaning',
        'chore',
        'chores',
        'mop',
        'mopping',
        'dust',
        'dusting',
        'vacuum',
        'vacuuming',
        'tidy',
        'tidying',
        'scrub',
        'scrubbing',
        'sanitize',
        'sanitizing',
        'dishes',
        'wash dishes',
        'washing dishes',
        'clean room',
        'clean bedroom',
        'clean kitchen',
        'clean bathroom',
      ],
    )) {
      return TaskIconType.cleaning;
    }

    if (_containsAny(
      text,
      [
        'gym',
        'workout',
        'exercise',
        'weights',
        'weightlifting',
        'lift',
        'lifting',
        'fitness',
        'training',
        'pushup',
        'pushups',
        'squat',
        'squats',
        'bench press',
      ],
    )) {
      return TaskIconType.workout;
    }

    if (_containsAny(
      text,
      [
        'run',
        'running',
        'jog',
        'jogging',
        'walk',
        'walking',
        'cardio',
        'steps',
        '5k',
        '10k',
      ],
    )) {
      return TaskIconType.running;
    }

    if (_containsAny(
      text,
      [
        'code',
        'coding',
        'program',
        'programming',
        'developer',
        'computer',
        'laptop',
        'work',
        'working',
        'project',
        'email',
        'meeting',
        'presentation',
        'design',
        'editing',
        'website',
        'app',
        'software',
      ],
    )) {
      return TaskIconType.computer;
    }

    if (_containsAny(
      text,
      [
        'cook',
        'cooking',
        'bake',
        'baking',
        'meal',
        'food',
        'kitchen',
        'dinner',
        'lunch',
        'breakfast',
        'recipe',
      ],
    )) {
      return TaskIconType.cooking;
    }

    if (_containsAny(
      text,
      [
        'laundry',
        'wash clothes',
        'washing clothes',
        'fold clothes',
        'folding clothes',
        'washer',
        'washing machine',
        'iron clothes',
        'ironing',
      ],
    )) {
      return TaskIconType.laundry;
    }

    if (_containsAny(
      text,
      [
        'meditate',
        'meditation',
        'mindfulness',
        'breathing',
        'breathe',
        'relax',
        'relaxing',
        'yoga',
        'pray',
        'prayer',
      ],
    )) {
      return TaskIconType.meditation;
    }

    if (_containsAny(
      text,
      [
        'garden',
        'gardening',
        'plant',
        'plants',
        'water plants',
        'watering plants',
        'flowers',
        'lawn',
        'yard',
        'mow',
        'mowing',
      ],
    )) {
      return TaskIconType.garden;
    }

    if (_containsAny(
      text,
      [
        'sleep',
        'sleeping',
        'nap',
        'napping',
        'bedtime',
        'go to bed',
        'rest',
      ],
    )) {
      return TaskIconType.sleep;
    }

    if (_containsAny(
      text,
      [
        'shop',
        'shopping',
        'groceries',
        'grocery',
        'buy',
        'store',
        'supermarket',
      ],
    )) {
      return TaskIconType.shopping;
    }

    if (_containsAny(
      text,
      [
        'drink water',
        'water',
        'hydrate',
        'hydration',
        'drink',
      ],
    )) {
      return TaskIconType.hydration;
    }

    if (_containsAny(
      text,
      [
        'medicine',
        'medication',
        'pill',
        'pills',
        'vitamin',
        'vitamins',
        'doctor',
        'appointment',
        'health',
      ],
    )) {
      return TaskIconType.health;
    }

    if (_containsAny(
      text,
      [
        'music',
        'song',
        'sing',
        'singing',
        'guitar',
        'piano',
        'drums',
        'instrument',
      ],
    )) {
      return TaskIconType.music;
    }

    if (_containsAny(
      text,
      [
        'call',
        'phone',
        'telephone',
        'facetime',
        'video call',
      ],
    )) {
      return TaskIconType.phone;
    }

    if (_containsAny(
      text,
      [
        'dog',
        'cat',
        'pet',
        'pets',
        'feed dog',
        'feed cat',
        'walk dog',
        'animal',
      ],
    )) {
      return TaskIconType.pet;
    }

    if (_containsAny(
      text,
      [
        'shower',
        'bath',
        'brush teeth',
        'teeth',
        'skincare',
        'skin care',
        'self care',
        'self-care',
        'groom',
        'grooming',
      ],
    )) {
      return TaskIconType.selfCare;
    }

    return TaskIconType.generic;
  }

  bool _containsAny(
    String text,
    List<String> keywords,
  ) {
    for (final keyword in keywords) {
      final normalized = keyword.toLowerCase();

      if (normalized.contains(' ')) {
        if (text.contains(normalized)) {
          return true;
        }

        continue;
      }

      final expression = RegExp(
        r'(^|\W)' +
            RegExp.escape(normalized) +
            r'($|\W)',
      );

      if (expression.hasMatch(text)) {
        return true;
      }
    }

    return false;
  }

  // ===========================================================
  // ICON PICKER
  // ===========================================================

  void _showTaskIconPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: widget.isDarkMode
          ? _T.surface
          : Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(26),
        ),
      ),
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: .72,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                20,
                4,
                20,
                20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose Task Icon',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 5),

                  const Text(
                    'TaskProof can choose automatically from the task name, or you can pick one yourself.',
                    style: TextStyle(
                      color: Color(0xFF777A84),
                      fontSize: 13,
                    ),
                  ),

                  const SizedBox(height: 17),

                  InkWell(
                    onTap: () {
                      setState(() {
                        taskIconManuallySelected = false;

                        selectedTaskIcon =
                            _getSuggestedTaskIcon(
                          taskNameController.text,
                        );
                      });

                      Navigator.pop(context);
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: !taskIconManuallySelected
                            ? const Color(0xFFFFECEE)
                            : const Color(0xFFF7F7F9),
                        borderRadius: BorderRadius.circular(
                          14,
                        ),
                        border: Border.all(
                          color: !taskIconManuallySelected
                              ? _C.red
                              : const Color(0xFFE5E6EA),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: widget.isDarkMode
                                  ? _T.selected
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(
                                11,
                              ),
                            ),
                            child: const Icon(
                              Icons.auto_awesome_rounded,
                              color: _C.red,
                            ),
                          ),

                          const SizedBox(width: 12),

                          const Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Automatic',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Changes automatically as you type.',
                                  style: TextStyle(
                                    color: Color(
                                      0xFF777A84,
                                    ),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          if (!taskIconManuallySelected)
                            const Icon(
                              Icons.check_rounded,
                              color: _C.red,
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    'Choose manually',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Expanded(
                    child: GridView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: TaskIconType.values.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: .82,
                      ),
                      itemBuilder: (
                        context,
                        index,
                      ) {
                        final type =
                            TaskIconType.values[index];

                        final selected =
                            taskIconManuallySelected &&
                                selectedTaskIcon == type;

                        return _TaskIconPickerItem(
                          type: type,
                          selected: selected,
                          onTap: () {
                            setState(() {
                              selectedTaskIcon = type;
                              taskIconManuallySelected = true;
                            });

                            Navigator.pop(context);
                          },
                        );
                      },
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
  // DURATION
  // ===========================================================

  void _changeHours(
    int value,
  ) {
    setState(() {
      hours = value;

      if (hours == 24) {
        minutes = 0;
        seconds = 0;

        if (_minutesController.hasClients) {
          _minutesController.jumpToItem(0);
        }

        if (_secondsController.hasClients) {
          _secondsController.jumpToItem(0);
        }
      }
    });
  }

  void _changeMinutes(
    int value,
  ) {
    if (hours == 24) {
      if (_minutesController.hasClients) {
        _minutesController.jumpToItem(0);
      }

      return;
    }

    setState(() {
      minutes = value;
    });
  }

  void _changeSeconds(
    int value,
  ) {
    if (hours == 24) {
      if (_secondsController.hasClients) {
        _secondsController.jumpToItem(0);
      }

      return;
    }

    setState(() {
      seconds = value;
    });
  }

  Widget _buildDurationPicker() {
    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final timerWidth =
            constraints.maxWidth < 350
                ? constraints.maxWidth * .74
                : 250.0;

        return Center(
          child: Container(
            width: timerWidth,
            height: 170,
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: widget.isDarkMode
                  ? _T.surface
                  : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: widget.isDarkMode
                    ? _T.border
                    : const Color(0xFFCACDD5),
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _DurationWheel(
                  controller: _hoursController,
                  selectedValue: hours,
                  itemCount: 25,
                  label: 'HOURS',
                  onChanged: _changeHours,
                ),

                const _DurationColon(),

                _DurationWheel(
                  controller: _minutesController,
                  selectedValue: minutes,
                  itemCount: 60,
                  label: 'MINUTES',
                  onChanged: _changeMinutes,
                ),

                const _DurationColon(),

                _DurationWheel(
                  controller: _secondsController,
                  selectedValue: seconds,
                  itemCount: 60,
                  label: 'SECONDS',
                  onChanged: _changeSeconds,
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

  Widget _buildScheduleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // =====================================================
        // HEADER
        // =====================================================

        Row(
          children: [
            Text(
              'Schedule',
              style: TextStyle(
                color: widget.isDarkMode
                    ? _T.text
                    : Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(width: 5),

            Text(
              '(Optional)',
              style: TextStyle(
                color: widget.isDarkMode
                    ? _T.muted
                    : const Color(0xFF777A84),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),

            const Spacer(),

            // When ON, the switch moves here.
            if (scheduleEnabled)
              Switch(
                value: true,
                onChanged: _setScheduleEnabled,
                activeThumbColor: Colors.white,
                activeTrackColor: _C.red,
                trackOutlineColor:
                    WidgetStateProperty.all(
                  Colors.transparent,
                ),
              ),
          ],
        ),

        const SizedBox(height: 10),

        AnimatedSwitcher(
          duration: const Duration(
            milliseconds: 220,
          ),
          transitionBuilder: (
            child,
            animation,
          ) {
            return SizeTransition(
              sizeFactor: animation,
              axisAlignment: -1,
              child: FadeTransition(
                opacity: animation,
                child: child,
              ),
            );
          },
          child: scheduleEnabled
              ? _buildScheduleEnabled()
              : _buildScheduleDisabled(),
        ),
      ],
    );
  }

  Widget _buildScheduleDisabled() {
    return Column(
      key: const ValueKey(
        'scheduleDisabled',
      ),
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            _setScheduleEnabled(true);
          },
          child: Container(
            height: 62,
            padding: const EdgeInsets.symmetric(
              horizontal: 13,
            ),
            decoration: BoxDecoration(
              color: widget.isDarkMode
                  ? _T.surface
                  : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: widget.isDarkMode
                    ? _T.border
                    : const Color(0xFFCACDD5),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness ==
                          Brightness.dark
                      ? const Color(0xFF28171B)
                      : const Color(0xFFFFECEE),
                    borderRadius: BorderRadius.circular(
                      10,
                    ),
                  ),
                  child: const Icon(
                    Icons.calendar_month_outlined,
                    color: _C.red,
                    size: 23,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Text(
                    'Schedule for later',
                    style: TextStyle(
                      color: widget.isDarkMode
                          ? _T.text
                          : Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

                Switch(
                  value: false,
                  onChanged: _setScheduleEnabled,
                  activeThumbColor: Colors.white,
                  activeTrackColor: _C.red,
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor:
                      const Color(
                    0xFFD8DAE1,
                  ),
                  trackOutlineColor:
                      WidgetStateProperty.all(
                    Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 9),

        Text(
          'Turn on to choose a date and time.',
          style: TextStyle(
            color: widget.isDarkMode
                ? _T.muted
                : const Color(0xFF777A84),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleEnabled() {
    return Column(
      key: const ValueKey(
        'scheduleEnabled',
      ),
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: widget.isDarkMode
                ? _T.surface
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.isDarkMode
                  ? _T.border
                  : const Color(0xFFCACDD5),
              width: 1.2,
            ),
          ),
          child: Column(
            children: [
              _SchedulePickerRow(
                icon: Icons.calendar_today_outlined,
                title: 'Date',
                subtitle: 'Choose a date',
                value: _formattedScheduleDate,
                onTap: _chooseScheduleDate,
              ),

              const Padding(
                padding: EdgeInsets.only(
                  left: 64,
                  right: 13,
                ),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFE2E3E7),
                ),
              ),

              _SchedulePickerRow(
                icon: Icons.schedule_rounded,
                title: 'Time',
                subtitle: 'Choose a time',
                value: _formattedScheduleTime,
                onTap: _chooseScheduleTime,
              ),
            ],
          ),
        ),

        const SizedBox(height: 9),

        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              color: _C.red,
              size: 17,
            ),

            SizedBox(width: 5),

            Flexible(
              child: Text(
                "You'll be reminded when it's time to start.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF676A74),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _setScheduleEnabled(
    bool enabled,
  ) {
    setState(() {
      scheduleEnabled = enabled;

      if (enabled) {
        final next = DateTime.now().add(
          const Duration(hours: 1),
        );

        selectedScheduleDate ??= DateTime(
          next.year,
          next.month,
          next.day,
        );

        selectedScheduleTime ??=
            TimeOfDay.fromDateTime(
          next,
        );
      }
    });
  }

  Future<void> _chooseScheduleDate() async {
    final now = DateTime.now();

    final today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final picked = await showDatePicker(
      context: context,
      initialDate:
          selectedScheduleDate ?? today,
      firstDate: today,
      lastDate: DateTime(
        now.year + 3,
        12,
        31,
      ),
      builder: (
        context,
        child,
      ) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: widget.isDarkMode
                ? const ColorScheme.dark(
                    primary: _C.red,
                    onPrimary: Colors.white,
                    surface: _T.surface,
                    onSurface: _T.text,
                  )
                : const ColorScheme.light(
                    primary: _C.red,
                    onPrimary: Colors.white,
                    onSurface: Colors.black,
                  ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      selectedScheduleDate = picked;
    });
  }

  Future<void> _chooseScheduleTime() async {
    final initial =
        selectedScheduleTime ??
            TimeOfDay.fromDateTime(
              DateTime.now().add(
                const Duration(hours: 1),
              ),
            );

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (
        context,
        child,
      ) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: widget.isDarkMode
                ? const ColorScheme.dark(
                    primary: _C.red,
                    onPrimary: Colors.white,
                    surface: _T.surface,
                    onSurface: _T.text,
                  )
                : const ColorScheme.light(
                    primary: _C.red,
                    onPrimary: Colors.white,
                    onSurface: Colors.black,
                  ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      selectedScheduleTime = picked;
    });
  }

  DateTime? get _selectedScheduledDateTime {
    if (!scheduleEnabled ||
        selectedScheduleDate == null ||
        selectedScheduleTime == null) {
      return null;
    }

    final date = selectedScheduleDate!;
    final time = selectedScheduleTime!;

    return DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
  }

  String get _formattedScheduleDate {
    final date = selectedScheduleDate;

    if (date == null) {
      return 'Choose date';
    }

    final now = DateTime.now();

    final today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final selected = DateTime(
      date.year,
      date.month,
      date.day,
    );

    if (DateUtils.isSameDay(
      selected,
      today,
    )) {
      return 'Today, ${_monthName(date.month)} ${date.day}';
    }

    final tomorrow = today.add(
      const Duration(days: 1),
    );

    if (DateUtils.isSameDay(
      selected,
      tomorrow,
    )) {
      return 'Tomorrow, ${_monthName(date.month)} ${date.day}';
    }

    return '${_monthName(date.month)} ${date.day}, ${date.year}';
  }

  String get _formattedScheduleTime {
    final time = selectedScheduleTime;

    if (time == null) {
      return 'Choose time';
    }

    int hour = time.hour;

    final suffix = hour >= 12
        ? 'PM'
        : 'AM';

    hour %= 12;

    if (hour == 0) {
      hour = 12;
    }

    final minute = time.minute
        .toString()
        .padLeft(
          2,
          '0',
        );

    return '$hour:$minute $suffix';
  }

  String _monthName(
    int month,
  ) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return months[month - 1];
  }

  // ===========================================================
  // VERIFICATION
  // ===========================================================

  bool get _dualVerificationActive {
    return stayInPosition && objectInFrame;
  }

  void _toggleStayInPosition() {
    // Turning the currently-selected method off is always allowed.
    if (stayInPosition) {
      setState(() {
        stayInPosition = false;
      });
      return;
    }

    // Free users can use either method, but combining both is Pro.
    if (objectInFrame && !isPro) {
      _showUpgradeDialog(
        attemptedMethod: 'Stay in Position',
      );
      return;
    }

    setState(() {
      stayInPosition = true;
    });
  }

  void _toggleObjectInFrame() {
    // Turning the currently-selected method off is always allowed.
    if (objectInFrame) {
      setState(() {
        objectInFrame = false;
      });
      return;
    }

    // Free users can use either method, but combining both is Pro.
    if (stayInPosition && !isPro) {
      _showUpgradeDialog(
        attemptedMethod: 'Object Must Be in Frame',
      );
      return;
    }

    setState(() {
      objectInFrame = true;
    });
  }

  Widget _buildVerificationRules() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: widget.isDarkMode
                ? _T.surface
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.isDarkMode
                  ? _T.border
                  : const Color(0xFFCACDD5),
              width: 1.2,
            ),
          ),
          child: Column(
            children: [
              _VerificationRow(
                iconType: _VerificationIconType.person,
                title: 'Stay in Position',
                subtitle:
                    'Keep yourself within your reference position.',
                checked: stayInPosition,
                onTap: _toggleStayInPosition,
              ),

              const _InnerDivider(),

              _VerificationRow(
                iconType: _VerificationIconType.object,
                title: 'Object Must Be in Frame',
                subtitle:
                    'Keep the selected object visible in the frame.',
                checked: objectInFrame,
                onTap: _toggleObjectInFrame,
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // This is a status/footer, not a third selectable verification rule.
        _DualVerificationFooter(
          active: _dualVerificationActive,
          isPro: isPro,
        ),
      ],
    );
  }

  // ===========================================================
  // REFERENCE SETUP
  // ===========================================================

  String get _referenceDescription {
    if (stayInPosition && objectInFrame) {
      return 'Capture both your position and required objects.';
    }

    if (stayInPosition) {
      return 'Capture the position you should maintain.';
    }

    if (objectInFrame) {
      return 'Capture the objects that must remain in frame.';
    }

    return 'Select a verification rule to add references.';
  }

  Widget _buildReferenceSetup() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: widget.isDarkMode
            ? _T.surface
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.isDarkMode
              ? _T.border
              : const Color(0xFFCACDD5),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      child: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          final compact =
              constraints.maxWidth < 330;

          final tileSize =
              compact ? 52.0 : 64.0;

          return Column(
            children: [
              if (stayInPosition)
                _ReferenceRow(
                  title: 'Reference Position',
                  subtitle:
                      'Capture the pose/position you should maintain.',
                  trailing: Align(
                    alignment: Alignment.centerLeft,
                    child: _CaptureTile(
                      size: tileSize,
                      captured:
                          referencePositionCaptured,
                      onTap:
                          _captureReferencePosition,
                    ),
                  ),
                ),

              if (stayInPosition && objectInFrame)
                const Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: 10,
                  ),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFE2E3E7),
                  ),
                ),

              if (objectInFrame)
                _ReferenceRow(
                  title: 'Required Objects',
                  subtitle:
                      'Add up to 3 objects that must stay in frame.',
                  trailing: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children:
                          _buildObjectCaptureTiles(
                        tileSize,
                        compact,
                      ),
                    ),
                  ),
                ),

              if (!stayInPosition &&
                  !objectInFrame)
                const SizedBox(
                  height: 90,
                  child: Center(
                    child: Text(
                      'Choose a verification rule above.',
                      style: TextStyle(
                        color: Color(0xFF858995),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildObjectCaptureTiles(
    double tileSize,
    bool compact,
  ) {
    final widgets = <Widget>[];

    for (int i = 0; i < 3; i++) {
      if (i < capturedObjects) {
        widgets.add(
          _CapturedObjectTile(
            size: tileSize,
          ),
        );
      } else if (i == capturedObjects &&
          capturedObjects < 3) {
        widgets.add(
          _CaptureTile(
            size: tileSize,
            captured: false,
            onTap: _captureObject,
          ),
        );
      } else {
        widgets.add(
          _EmptyCaptureTile(
            size: tileSize,
          ),
        );
      }

      if (i != 2) {
        widgets.add(
          const SizedBox(width: 7),
        );
      }
    }

    widgets.add(
      const SizedBox(width: 9),
    );

    widgets.add(
      _CaptureCounter(
        current: capturedObjects,
        total: 3,
        compact: compact,
      ),
    );

    return widgets;
  }

  // ===========================================================
  // ALARM
  // ===========================================================

  Widget _buildAlarmSound() {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _selectAlarm,
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
        ),
        decoration: BoxDecoration(
          color: widget.isDarkMode
              ? _T.surface
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: widget.isDarkMode
                ? _T.border
                : const Color(0xFFCACDD5),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness ==
                    Brightness.dark
                ? const Color(0xFF28171B)
                : const Color(0xFFFFECEE),
                borderRadius: BorderRadius.circular(
                  11,
                ),
              ),
              child: const Icon(
                Icons.music_note_rounded,
                color: _C.red,
                size: 26,
              ),
            ),

            const SizedBox(width: 13),

            Expanded(
              child: Text(
                selectedAlarm,
                style: TextStyle(
                  color: widget.isDarkMode
                      ? _T.text
                      : Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            Icon(
              Icons.chevron_right_rounded,
              color: widget.isDarkMode
                  ? _T.muted
                  : const Color(0xFF4F5158),
              size: 28,
            ),
          ],
        ),
      ),
    );
  }

  void _selectAlarm() {
    final alarms = [
      'Default Alarm',
      'Pulse',
      'Bell',
      'Alert',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: widget.isDarkMode
          ? _T.surface
          : Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
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
                const Text(
                  'Alarm Sound',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 12),

                ...alarms.map(
                  (alarm) {
                    final selected =
                        selectedAlarm == alarm;

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.music_note_rounded,
                        color: selected
                            ? _C.red
                            : _C.grey,
                      ),
                      title: Text(
                        alarm,
                        style: TextStyle(
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      trailing: selected
                          ? const Icon(
                              Icons.check_rounded,
                              color: _C.red,
                            )
                          : null,
                      onTap: () {
                        setState(() {
                          selectedAlarm = alarm;
                        });

                        Navigator.pop(context);
                      },
                    );
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
  // SENSITIVITY
  // ===========================================================

  Widget _buildSensitivity() {
    return Column(
      children: [
        LayoutBuilder(
          builder: (
            context,
            constraints,
          ) {
            final activeWidth =
                constraints.maxWidth *
                    sensitivity;

            return SizedBox(
              height: 34,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Positioned(
                    left: 6,
                    right: 6,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: const Color(
                          0xFFDADCE1,
                        ),
                        borderRadius:
                            BorderRadius.circular(
                          999,
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    left: 6,
                    width: activeWidth > 12
                        ? activeWidth - 6
                        : 6,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(
                          999,
                        ),
                        gradient:
                            const LinearGradient(
                          colors: [
                            Color(0xFFFF101C),
                            Color(0xFFFF7A00),
                          ],
                        ),
                      ),
                    ),
                  ),

                  SliderTheme(
                    data: SliderTheme.of(context)
                        .copyWith(
                      activeTrackColor:
                          Colors.transparent,
                      inactiveTrackColor:
                          Colors.transparent,
                      trackHeight: 0,
                      overlayColor:
                          Colors.transparent,
                      thumbColor: Colors.white,
                      thumbShape:
                          const RoundSliderThumbShape(
                        enabledThumbRadius: 11,
                        elevation: 3,
                        pressedElevation: 5,
                      ),
                    ),
                    child: Slider(
                      value: sensitivity,
                      min: 0,
                      max: 1,
                      onChanged: (value) {
                        setState(() {
                          sensitivity = value;
                        });
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 3,
          ),
          child: Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Low',
                style: TextStyle(
                  color: Color(0xFF555861),
                  fontSize: 12,
                ),
              ),
              Text(
                'Medium',
                style: TextStyle(
                  color: Color(0xFF25262B),
                  fontSize: 12,
                ),
              ),
              Text(
                'High',
                style: TextStyle(
                  color: Color(0xFF555861),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================
  // CAPTURE PLACEHOLDERS
  // ===========================================================

  void _captureReferencePosition() {
    setState(() {
      referencePositionCaptured = true;
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Reference position capture placeholder',
          ),
        ),
      );
  }

  void _captureObject() {
    if (capturedObjects >= 3) {
      return;
    }

    setState(() {
      capturedObjects++;
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$capturedObjects/3 objects captured',
          ),
        ),
      );
  }

  // ===========================================================
  // PRO
  // ===========================================================

  void _showUpgradeDialog({
    required String attemptedMethod,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              20,
              20,
              20,
              16,
            ),
            decoration: BoxDecoration(
              color: widget.isDarkMode
                  ? _T.surface
                  : Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: const Color(0xFFFFD8DC),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _DualVerificationHeroIcon(),

                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        'Unlock Dual Verification',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: widget.isDarkMode
                              ? _T.text
                              : Colors.black,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),

                    const SizedBox(width: 7),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _C.red,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'PRO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                Text(
                  'Free tasks can use one verification method at a time. '
                  'To use $attemptedMethod together with your current method, '
                  'upgrade to TaskProof Pro.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: widget.isDarkMode
                        ? _T.muted
                        : const Color(0xFF555861),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  'Dual Verification checks both your position and required '
                  'object during the same session.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: widget.isDarkMode
                        ? _T.muted
                        : const Color(0xFF777A84),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),

                const SizedBox(height: 18),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _C.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    onPressed: () {
                      // TODO: Replace this with your real Pro purchase screen.
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Upgrade to TaskProof Pro',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 4),

                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: Text(
                    'Not now',
                    style: TextStyle(
                      color: widget.isDarkMode
                          ? _T.muted
                          : const Color(0xFF555861),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ===========================================================
  // SAVE
  // ===========================================================

  void _saveTask() {
    final taskName =
        taskNameController.text.trim();

    if (taskName.isEmpty) {
      _showMessage(
        'Enter a task name first.',
      );
      return;
    }

    if (hours == 0 &&
        minutes == 0 &&
        seconds == 0) {
      _showMessage(
        'Task duration must be longer than 0 seconds.',
      );
      return;
    }

    if (!stayInPosition &&
        !objectInFrame) {
      _showMessage(
        'Choose at least one verification rule.',
      );
      return;
    }

    DateTime? scheduledFor;

    if (scheduleEnabled) {
      scheduledFor =
          _selectedScheduledDateTime;

      if (scheduledFor == null) {
        _showMessage(
          'Choose a date and time for this task.',
        );
        return;
      }

      if (!scheduledFor.isAfter(
        DateTime.now(),
      )) {
        _showMessage(
          'Choose a scheduled time in the future.',
        );
        return;
      }
    }

    final task = TaskData(
      id: DateTime.now()
          .microsecondsSinceEpoch
          .toString(),
      name: taskName,
      icon: selectedTaskIcon,
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      stayInPosition: stayInPosition,
      objectInFrame: objectInFrame,
      alarm: selectedAlarm,
      sensitivity: sensitivity,
      status: scheduleEnabled
          ? TaskStatus.scheduled
          : TaskStatus.ready,
      scheduledFor: scheduledFor,
    );

    Navigator.pop(
      context,
      task,
    );
  }

  void _showMessage(
    String text,
  ) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
        ),
      );
  }
}

// =============================================================
// SCHEDULE PICKER ROW
// =============================================================

class _SchedulePickerRow
    extends StatelessWidget {
  const _SchedulePickerRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 10,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness ==
                Brightness.dark
            ? const Color(0xFF28171B)
            : const Color(0xFFFFECEE),
                  borderRadius: BorderRadius.circular(
                    10,
                  ),
                ),
                child: Icon(
                  icon,
                  color: _C.red,
                  size: 22,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Theme.of(context).brightness ==
                                Brightness.dark
                            ? _T.text
                            : Colors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 2),

                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Theme.of(context).brightness ==
                                Brightness.dark
                            ? _T.muted
                            : const Color(0xFF777A84),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).brightness ==
                            Brightness.dark
                        ? _T.text
                        : Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              const SizedBox(width: 5),

              Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(context).brightness ==
                        Brightness.dark
                    ? _T.muted
                    : const Color(0xFF34363D),
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================
// TASK ICON TILE
// =============================================================

class _TaskIconTile
    extends StatelessWidget {
  const _TaskIconTile({
    required this.type,
    this.size = 50,
  });

  final TaskIconType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (type == TaskIconType.generic) {
      return CustomPaint(
        foregroundPainter:
            const _ScanCornersPainter(
          color: _C.red,
          inset: 7,
          length: 7,
          strokeWidth: 1.7,
        ),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFFFECEE),
            borderRadius: BorderRadius.circular(
              11,
            ),
          ),
          child: CustomPaint(
            size: const Size(27, 27),
            painter: _GenericTaskPainter(
              color: Theme.of(context).brightness ==
                      Brightness.dark
                  ? _T.text
                  : const Color(0xFF24262D),
            ),
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFFECEE),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(
        _taskIconData(type),
        color: Theme.of(context).brightness ==
                Brightness.dark
            ? _T.text
            : const Color(0xFF202229),
        size: size * .52,
      ),
    );
  }
}

class _GenericTaskPainter
    extends CustomPainter {
  const _GenericTaskPainter({
    required this.color,
  });

  final Color color;

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.7
      ..strokeCap = StrokeCap.round;

    final left = size.width * .22;
    final right = size.width * .78;

    for (final y in [
      .28,
      .50,
      .72,
    ]) {
      canvas.drawLine(
        Offset(
          left,
          size.height * y,
        ),
        Offset(
          right,
          size.height * y,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) {
    return oldDelegate is! _GenericTaskPainter ||
        oldDelegate.color != color;
  }
}

// =============================================================
// ICON PICKER ITEM
// =============================================================

class _TaskIconPickerItem
    extends StatelessWidget {
  const _TaskIconPickerItem({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final TaskIconType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness ==
                  Brightness.dark
              ? (selected
                  ? const Color(0xFF271418)
                  : _T.selected)
              : (selected
                  ? const Color(0xFFFFF1F2)
                  : const Color(0xFFF9F9FA)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? _C.red
                : (Theme.of(context).brightness ==
                        Brightness.dark
                    ? _T.border
                    : const Color(0xFFE6E7EB)),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _TaskIconTile(
              type: type,
              size: 45,
            ),

            const SizedBox(height: 6),

            Text(
              _taskIconLabel(type),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? _C.red
                    : (Theme.of(context).brightness ==
                            Brightness.dark
                        ? _T.text
                        : const Color(0xFF33353B)),
                fontSize: 10,
                fontWeight: selected
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// TASK ICON HELPERS
// =============================================================

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

String _taskIconLabel(
  TaskIconType type,
) {
  switch (type) {
    case TaskIconType.generic:
      return 'Task';
    case TaskIconType.study:
      return 'Study';
    case TaskIconType.cleaning:
      return 'Clean';
    case TaskIconType.workout:
      return 'Workout';
    case TaskIconType.running:
      return 'Run';
    case TaskIconType.computer:
      return 'Work';
    case TaskIconType.cooking:
      return 'Cook';
    case TaskIconType.laundry:
      return 'Laundry';
    case TaskIconType.meditation:
      return 'Mindful';
    case TaskIconType.garden:
      return 'Garden';
    case TaskIconType.sleep:
      return 'Sleep';
    case TaskIconType.shopping:
      return 'Shopping';
    case TaskIconType.hydration:
      return 'Water';
    case TaskIconType.health:
      return 'Health';
    case TaskIconType.music:
      return 'Music';
    case TaskIconType.phone:
      return 'Call';
    case TaskIconType.pet:
      return 'Pet';
    case TaskIconType.selfCare:
      return 'Self Care';
  }
}

// =============================================================
// DURATION WHEEL
// =============================================================

class _DurationWheel
    extends StatelessWidget {
  const _DurationWheel({
    required this.controller,
    required this.selectedValue,
    required this.itemCount,
    required this.label,
    required this.onChanged,
  });

  final FixedExtentScrollController controller;
  final int selectedValue;
  final int itemCount;
  final String label;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      child: Column(
        children: [
          SizedBox(
            height: 112,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ListWheelScrollView.useDelegate(
                  controller: controller,
                  itemExtent: 36,
                  diameterRatio: 100,
                  perspective: .0001,
                  physics:
                      const FixedExtentScrollPhysics(),
                  onSelectedItemChanged: onChanged,
                  childDelegate:
                      ListWheelChildBuilderDelegate(
                    childCount: itemCount,
                    builder: (
                      context,
                      index,
                    ) {
                      final selected =
                          index == selectedValue;

                      return Center(
                        child: Text(
                          index
                              .toString()
                              .padLeft(2, '0'),
                          style: TextStyle(
                            color: selected
                                ? (Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? _T.text
                                    : Colors.black)
                                : (Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? _T.muted
                                    : const Color(
                                        0xFF90939C,
                                      )),
                            fontSize:
                                selected ? 28 : 15,
                            fontWeight: selected
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                Positioned(
                  top: 37,
                  left: 4,
                  right: 4,
                  child: IgnorePointer(
                    child: Container(
                      height: 1.3,
                      color: Theme.of(context).brightness ==
                              Brightness.dark
                          ? _T.border
                          : Colors.black,
                    ),
                  ),
                ),

                Positioned(
                  bottom: 37,
                  left: 4,
                  right: 4,
                  child: IgnorePointer(
                    child: Container(
                      height: 1.3,
                      color: Theme.of(context).brightness ==
                              Brightness.dark
                          ? _T.border
                          : Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 3),

          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF555861),
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _DurationColon
    extends StatelessWidget {
  const _DurationColon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 13,
      child: Column(
        children: [
          SizedBox(
            height: 112,
            child: Center(
              child: Text(
                ':',
                style: TextStyle(
                  color: Theme.of(context).brightness ==
                          Brightness.dark
                      ? _T.text
                      : Colors.black,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// =============================================================
// VERIFICATION WIDGETS
// =============================================================

enum _VerificationIconType {
  person,
  object,
  dual,
}

class _VerificationRow
    extends StatelessWidget {
  const _VerificationRow({
    required this.iconType,
    required this.title,
    required this.subtitle,
    required this.checked,
    required this.onTap,
  }) : showPro = false, locked = false;

  final _VerificationIconType iconType;
  final String title;
  final String subtitle;
  final bool checked;
  final bool locked;
  final bool showPro;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            12,
            10,
            12,
            10,
          ),
          child: Row(
            children: [
              _ScanIconTile(
                type: iconType,
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 7,
                      crossAxisAlignment:
                          WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: Theme.of(context).brightness ==
                                    Brightness.dark
                                ? _T.text
                                : Colors.black,
                            fontSize: 16,
                            fontWeight:
                                FontWeight.w800,
                          ),
                        ),

                        if (showPro)
                          Container(
                            padding:
                                const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _C.red,
                              borderRadius:
                                  BorderRadius.circular(
                                5,
                              ),
                            ),
                            child: const Text(
                              'Pro',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight:
                                    FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Theme.of(context).brightness ==
                                Brightness.dark
                            ? _T.muted
                            : const Color(0xFF555861),
                        fontSize: 13,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              if (locked)
                const Icon(
                  Icons.lock_outline_rounded,
                  color: Color(0xFF686B74),
                  size: 26,
                )
              else
                _CheckBox(
                  checked: checked,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanIconTile
    extends StatelessWidget {
  const _ScanIconTile({
    required this.type,
  });

  final _VerificationIconType type;

  @override
  Widget build(BuildContext context) {
    Widget icon;

    switch (type) {
      case _VerificationIconType.person:
        icon = const Icon(
          Icons.person_outline_rounded,
          color: _C.red,
          size: 26,
        );
        break;

      case _VerificationIconType.object:
        icon = const Icon(
          Icons.inventory_2_outlined,
          color: _C.red,
          size: 24,
        );
        break;

      case _VerificationIconType.dual:
        icon = const SizedBox(
          width: 32,
          height: 30,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                bottom: 2,
                child: Icon(
                  Icons.person_outline_rounded,
                  color: _C.red,
                  size: 25,
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Icon(
                  Icons.inventory_2_outlined,
                  color: _C.red,
                  size: 14,
                ),
              ),
            ],
          ),
        );
        break;
    }

    return CustomPaint(
      foregroundPainter:
          const _ScanCornersPainter(
        color: _C.red,
        inset: 7,
        length: 8,
        strokeWidth: 1.8,
      ),
      child: Container(
        width: 54,
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness ==
                  Brightness.dark
              ? const Color(0xFF28171B)
              : const Color(0xFFFFEBED),
          borderRadius: BorderRadius.circular(10),
        ),
        child: icon,
      ),
    );
  }
}


class _DualVerificationFooter extends StatelessWidget {
  const _DualVerificationFooter({
    required this.active,
    required this.isPro,
  });

  final bool active;
  final bool isPro;

  @override
  Widget build(BuildContext context) {
    final enabled = active && isPro;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        12,
        9,
        12,
        9,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness ==
                Brightness.dark
            ? (enabled
                ? const Color(0xFF271418)
                : _T.selected)
            : (enabled
                ? const Color(0xFFFFF0F2)
                : const Color(0xFFF7F7F9)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).brightness ==
                  Brightness.dark
              ? _T.border
              : (enabled
                  ? const Color(0xFFFFC8CE)
                  : const Color(0xFFE2E3E7)),
        ),
      ),
      child: Row(
        children: [
          _MiniDualVerificationIcon(
            active: enabled,
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Dual Verification',
                      style: TextStyle(
                        color: enabled
                            ? _C.red
                            : const Color(0xFF666A73),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: enabled
                            ? _C.red
                            : const Color(0xFF8B8E96),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        'PRO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  enabled
                      ? 'Both verification methods are active.'
                      : 'Select both methods to unlock combined verification.',
                  style: TextStyle(
                    color: enabled
                        ? const Color(0xFF555861)
                        : const Color(0xFF8A8D95),
                    fontSize: 11,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          Icon(
            enabled
                ? Icons.check_circle_rounded
                : Icons.lock_outline_rounded,
            color: enabled
                ? _C.red
                : const Color(0xFF7A7D86),
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _MiniDualVerificationIcon extends StatelessWidget {
  const _MiniDualVerificationIcon({
    required this.active,
  });

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? _C.red
        : const Color(0xFF7A7D86);

    return SizedBox(
      width: 36,
      height: 30,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            bottom: 2,
            child: Icon(
              Icons.person_outline_rounded,
              color: color,
              size: 24,
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Icon(
              Icons.inventory_2_outlined,
              color: color,
              size: 15,
            ),
          ),
          Positioned(
            left: 17,
            top: 5,
            child: Container(
              width: 8,
              height: 1.5,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _DualVerificationHeroIcon extends StatelessWidget {
  const _DualVerificationHeroIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 86,
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xFFFFECEE),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 16,
            child: Icon(
              Icons.person_outline_rounded,
              color: _C.red,
              size: 37,
            ),
          ),
          Positioned(
            right: 15,
            child: Icon(
              Icons.inventory_2_outlined,
              color: _C.red,
              size: 31,
            ),
          ),
          Positioned(
            bottom: 7,
            child: Icon(
              Icons.lock_rounded,
              color: Color(0xFF666A73),
              size: 19,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckBox
    extends StatelessWidget {
  const _CheckBox({
    required this.checked,
  });

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(
        milliseconds: 150,
      ),
      width: 27,
      height: 27,
      decoration: BoxDecoration(
        color: checked
            ? _C.red
            : (Theme.of(context).brightness ==
                    Brightness.dark
                ? _T.selected
                : const Color(0xFFF0F1F3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: checked
          ? const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 20,
            )
          : null,
    );
  }
}

// =============================================================
// REFERENCE WIDGETS
// =============================================================

class _ReferenceRow
    extends StatelessWidget {
  const _ReferenceRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: constraints.maxWidth * .36,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Theme.of(context).brightness ==
                              Brightness.dark
                          ? _T.text
                          : Colors.black,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Theme.of(context).brightness ==
                              Brightness.dark
                          ? _T.muted
                          : const Color(0xFF555861),
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            Expanded(
              child: trailing,
            ),
          ],
        );
      },
    );
  }
}

class _CaptureTile
    extends StatelessWidget {
  const _CaptureTile({
    required this.size,
    required this.captured,
    required this.onTap,
  });

  final double size;
  final bool captured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: const _DashedBorderPainter(
          color: Color(0xFFB7BAC3),
        ),
        foregroundPainter:
            const _ScanCornersPainter(
          color: _C.red,
          inset: 4,
          length: 8,
          strokeWidth: 1.8,
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: captured
                ? const Icon(
                    Icons.check_circle_rounded,
                    color: _C.red,
                    size: 27,
                  )
                : const Icon(
                    Icons.add_a_photo_outlined,
                    color: Color(0xFF9C9FA6),
                    size: 27,
                  ),
          ),
        ),
      ),
    );
  }
}

class _CapturedObjectTile
    extends StatelessWidget {
  const _CapturedObjectTile({
    required this.size,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _DashedBorderPainter(
        color: Color(0xFFB7BAC3),
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: const Center(
          child: Icon(
            Icons.check_circle_rounded,
            color: _C.red,
            size: 26,
          ),
        ),
      ),
    );
  }
}

class _EmptyCaptureTile
    extends StatelessWidget {
  const _EmptyCaptureTile({
    required this.size,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _DashedBorderPainter(
        color: Color(0xFFC4C6CD),
      ),
      child: SizedBox(
        width: size,
        height: size,
      ),
    );
  }
}

class _CaptureCounter
    extends StatelessWidget {
  const _CaptureCounter({
    required this.current,
    required this.total,
    required this.compact,
  });

  final int current;
  final int total;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 50 : 58,
      height: compact ? 52 : 62,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness ==
                Brightness.dark
            ? _T.selected
            : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(context).brightness ==
                  Brightness.dark
              ? _T.border
              : const Color(0xFFCDD0D7),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$current/$total',
            style: TextStyle(
              color: Theme.of(context).brightness ==
                      Brightness.dark
                  ? _T.text
                  : Colors.black,
              fontSize: compact ? 16 : 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            'Captured',
            style: TextStyle(
              color: const Color(0xFF555861),
              fontSize: compact ? 8 : 10,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// SECTION HELPERS
// =============================================================

class _SectionTitle
    extends StatelessWidget {
  const _SectionTitle(
    this.text,
  );

  final String text;

  @override
  Widget build(BuildContext context) {
    final dark =
        Theme.of(context).brightness ==
            Brightness.dark;

    return Text(
      text,
      style: TextStyle(
        color: dark ? _T.text : Colors.black,
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -.2,
      ),
    );
  }
}

class _SectionDivider
    extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 18,
      ),
      child: Divider(
        height: 2,
        thickness: 2,
        color: Theme.of(context).brightness ==
                Brightness.dark
            ? _T.border
            : const Color(0xFFCACDD5),
      ),
    );
  }
}

class _InnerDivider
    extends StatelessWidget {
  const _InnerDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
      ),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Theme.of(context).brightness ==
                Brightness.dark
            ? _T.border
            : const Color(0xFFE1E2E6),
      ),
    );
  }
}

// =============================================================
// PAINTERS
// =============================================================

class _DashedBorderPainter
    extends CustomPainter {
  const _DashedBorderPainter({
    required this.color,
  });

  final Color color;

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    const dash = 5.0;
    const gap = 4.0;

    void drawDashed(
      Offset start,
      Offset end,
    ) {
      final distance = (end - start).distance;

      if (distance == 0) {
        return;
      }

      final direction =
          (end - start) / distance;

      double drawn = 0;

      while (drawn < distance) {
        final startPoint =
            start + direction * drawn;

        final endDistance =
            (drawn + dash).clamp(
          0.0,
          distance,
        );

        final endPoint =
            start + direction * endDistance;

        canvas.drawLine(
          startPoint,
          endPoint,
          paint,
        );

        drawn += dash + gap;
      }
    }

    final left = 1.0;
    final top = 1.0;
    final right = size.width - 1;
    final bottom = size.height - 1;

    drawDashed(
      Offset(left, top),
      Offset(right, top),
    );

    drawDashed(
      Offset(right, top),
      Offset(right, bottom),
    );

    drawDashed(
      Offset(right, bottom),
      Offset(left, bottom),
    );

    drawDashed(
      Offset(left, bottom),
      Offset(left, top),
    );
  }

  @override
  bool shouldRepaint(
    covariant _DashedBorderPainter oldDelegate,
  ) {
    return oldDelegate.color != color;
  }
}

class _ScanCornersPainter
    extends CustomPainter {
  const _ScanCornersPainter({
    required this.color,
    required this.inset,
    required this.length,
    required this.strokeWidth,
  });

  final Color color;
  final double inset;
  final double length;
  final double strokeWidth;

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

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
    covariant _ScanCornersPainter oldDelegate,
  ) {
    return oldDelegate.color != color ||
        oldDelegate.inset != inset ||
        oldDelegate.length != length ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

// =============================================================
// COLORS
// =============================================================

class _C {
  static const red =
      Color(0xFFFF101C);

  static const grey =
      Color(0xFF858995);
}

// =============================================================
// DARK MODE COLORS
// =============================================================

class _T {
  static const background =
      Color(0xFF0B1016);

  static const surface =
      Color(0xFF10161D);

  static const selected =
      Color(0xFF171E27);

  static const border =
      Color(0xFF252D37);

  static const text =
      Color(0xFFF4F6F8);

  static const muted =
      Color(0xFF9DA8B8);
}