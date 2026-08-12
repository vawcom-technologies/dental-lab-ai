import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import 'app_buttons.dart';

/// Form field that stores ISO `yyyy-MM-dd` while showing a friendly DOB label.
class DobPickerField extends StatelessWidget {
  const DobPickerField({
    super.key,
    required this.controller,
    required this.labelText,
    this.onChanged,
  });

  final TextEditingController controller;
  final String labelText;
  final ValueChanged<String>? onChanged;

  static String formatDisplay(DateTime dob) {
    final age = DentalDatePickerDialog.ageInYears(dob);
    final date = DateFormat('MMM d, yyyy').format(dob);
    final ageLabel = age == 1 ? '1 year old' : '$age years old';
    return '$date · $ageLabel';
  }

  Future<void> _pick(BuildContext context) async {
    final current = DateTime.tryParse(controller.text.trim());
    final picked = await DentalDatePickerDialog.showForDateOfBirth(
      context: context,
      currentDob: current,
    );
    if (picked == null) return;
    final iso = DateFormat('yyyy-MM-dd').format(picked);
    controller.text = iso;
    onChanged?.call(iso);
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: controller.text,
      validator: (_) {
        final value = controller.text.trim();
        if (value.isEmpty) return 'Required';
        if (DateTime.tryParse(value) == null) return 'Invalid date';
        return null;
      },
      builder: (state) {
        final parsed = DateTime.tryParse(controller.text.trim());
        final hasValue = parsed != null;
        return InkWell(
          onTap: () async {
            await _pick(context);
            state.didChange(controller.text);
          },
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            isEmpty: !hasValue,
            decoration: InputDecoration(
              labelText: labelText,
              hintText: 'Tap to select',
              errorText: state.errorText,
              suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
            ),
            // Empty child when unset so label/hint don't collide.
            child: Text(
              hasValue ? formatDisplay(parsed) : '',
              style: AppFonts.style(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Simple scroll-wheel DOB picker (month / day / year).
class _DobWheelDialog extends StatefulWidget {
  const _DobWheelDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.title,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;

  @override
  State<_DobWheelDialog> createState() => _DobWheelDialogState();
}

class _DobWheelDialogState extends State<_DobWheelDialog> {
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _selected = DentalDatePickerDialog.dateOnly(widget.initialDate);
  }

  @override
  Widget build(BuildContext context) {
    final age = DentalDatePickerDialog.ageInYears(_selected);
    final header = DateFormat('MMM d, yyyy').format(_selected);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: DentalDatePickerColors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: DentalDatePickerColors.muted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      header,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: DentalDatePickerColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      age == 1 ? 'Age 1 year' : 'Age $age years',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: DentalDatePickerColors.active,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: DentalDatePickerColors.border),
              SizedBox(
                height: 216,
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: _selected,
                  minimumDate: widget.firstDate,
                  maximumDate: widget.lastDate,
                  onDateTimeChanged: (value) {
                    setState(() {
                      _selected = DentalDatePickerDialog.dateOnly(value);
                    });
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButtons.ghost(
                    onPressed: () => Navigator.of(context).pop(),
                    label: 'Cancel',
                  ),
                  const SizedBox(width: 8),
                  AppButtons.primary(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    label: 'Use this date',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Date picker colors — aliased to app tokens for a consistent iPad look.
class DentalDatePickerColors {
  static const primary = AppColors.navy;
  static const active = AppColors.dentalBlue;
  static const surface = AppColors.inset;
  static const text = AppColors.text;
  static const muted = AppColors.muted;
  static const border = AppColors.border;
  static const white = Colors.white;
}

/// Modern clinical date picker that replaces Material [showDatePicker].
class DentalDatePickerDialog extends StatefulWidget {
  const DentalDatePickerDialog({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    this.title = 'Select Date',
    this.showQuickPresets = true,
    this.forDateOfBirth = false,
    this.selectableDayPredicate,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;
  final bool showQuickPresets;

  /// Year-first flow with age readout — used for patient DOB.
  final bool forDateOfBirth;
  final bool Function(DateTime day)? selectableDayPredicate;

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime get today => dateOnly(DateTime.now());

  /// Typical adult starting point when no DOB is set yet.
  static DateTime defaultDobAnchor({int ageYears = 35}) {
    final now = today;
    return DateTime(now.year - ageYears, now.month, now.day);
  }

  static int ageInYears(DateTime dob, [DateTime? onDate]) {
    final on = dateOnly(onDate ?? DateTime.now());
    final birth = dateOnly(dob);
    var age = on.year - birth.year;
    if (on.month < birth.month ||
        (on.month == birth.month && on.day < birth.day)) {
      age -= 1;
    }
    return age < 0 ? 0 : age;
  }

  /// Shows the clinical date picker and returns the chosen day (date-only).
  static Future<DateTime?> show({
    required BuildContext context,
    required DateTime initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
    String title = 'Select Date',
    bool showQuickPresets = true,
    bool forDateOfBirth = false,
    bool Function(DateTime day)? selectableDayPredicate,
  }) {
    final first = dateOnly(firstDate ?? DateTime(1900));
    final last = dateOnly(lastDate ?? DateTime(2100));
    var initial = dateOnly(initialDate);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;

    return showCupertinoDialog<DateTime>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Material(
        type: MaterialType.transparency,
        child: DentalDatePickerDialog(
          initialDate: initial,
          firstDate: first,
          lastDate: last,
          title: title,
          showQuickPresets: showQuickPresets,
          forDateOfBirth: forDateOfBirth,
          selectableDayPredicate: selectableDayPredicate,
        ),
      ),
    );
  }

  /// Appointments / clinical scheduling — opens on **today**, no past days.
  static Future<DateTime?> showForAppointment({
    required BuildContext context,
    DateTime? initialDate,
    String title = 'Select Appointment Date',
    int bookingHorizonDays = 730,
    bool Function(DateTime day)? selectableDayPredicate,
  }) {
    final now = today;
    return show(
      context: context,
      initialDate: initialDate ?? now,
      firstDate: now,
      lastDate: now.add(Duration(days: bookingHorizonDays)),
      title: title,
      showQuickPresets: true,
      selectableDayPredicate: selectableDayPredicate,
    );
  }

  /// Patient date of birth — scroll wheels; defaults to ~35 years ago.
  static Future<DateTime?> showForDateOfBirth({
    required BuildContext context,
    DateTime? currentDob,
    String title = 'Date of Birth',
  }) {
    final now = today;
    final first = DateTime(1900);
    var initial = dateOnly(currentDob ?? defaultDobAnchor());
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(now)) initial = now;

    return showCupertinoDialog<DateTime>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Material(
        type: MaterialType.transparency,
        child: _DobWheelDialog(
          initialDate: initial,
          firstDate: first,
          lastDate: now,
          title: title,
        ),
      ),
    );
  }

  @override
  State<DentalDatePickerDialog> createState() => _DentalDatePickerDialogState();
}

class _DentalDatePickerDialogState extends State<DentalDatePickerDialog> {
  late DateTime _selectedDate;
  late DateTime _focusedMonth;
  late bool _pickingYear;
  /// 0 = year, 1 = month, 2 = day (DOB flow).
  late int _dobStep;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
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
  static const _monthShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _focusedMonth = DateTime(widget.initialDate.year, widget.initialDate.month);
    _pickingYear = widget.forDateOfBirth;
    _dobStep = widget.forDateOfBirth ? 0 : 2;
  }

  DateTime get _today => DentalDatePickerDialog.today;

  bool _isSelectable(DateTime day) {
    final d = DentalDatePickerDialog.dateOnly(day);
    if (d.isBefore(widget.firstDate) || d.isAfter(widget.lastDate)) {
      return false;
    }
    final pred = widget.selectableDayPredicate;
    if (pred != null && !pred(d)) return false;
    return true;
  }

  void _selectDate(DateTime day) {
    if (!_isSelectable(day)) return;
    setState(() {
      _selectedDate = DentalDatePickerDialog.dateOnly(day);
      _focusedMonth = DateTime(day.year, day.month);
      _pickingYear = false;
      if (widget.forDateOfBirth) _dobStep = 2;
    });
  }

  void _selectPreset(int daysFromToday) {
    final candidate = _today.add(Duration(days: daysFromToday));
    if (_isSelectable(candidate)) {
      _selectDate(candidate);
    }
  }

  void _shiftMonth(int delta) {
    final next = DateTime(_focusedMonth.year, _focusedMonth.month + delta);
    final firstMonth =
        DateTime(widget.firstDate.year, widget.firstDate.month);
    final lastMonth = DateTime(widget.lastDate.year, widget.lastDate.month);
    if (next.isBefore(firstMonth) || next.isAfter(lastMonth)) return;
    setState(() {
      _focusedMonth = next;
      _pickingYear = false;
      if (widget.forDateOfBirth) _dobStep = 2;
    });
  }

  void _applyYear(int year) {
    final month = _focusedMonth.month;
    var day = _selectedDate.day;
    final maxDay = DateTime(year, month + 1, 0).day;
    if (day > maxDay) day = maxDay;
    final candidate = DateTime(year, month, day);
    setState(() {
      _focusedMonth = DateTime(year, month);
      if (_isSelectable(candidate)) {
        _selectedDate = candidate;
      } else {
        // Clamp into range for this year.
        final clamped = candidate.isBefore(widget.firstDate)
            ? widget.firstDate
            : widget.lastDate;
        if (clamped.year == year) {
          _selectedDate = clamped;
          _focusedMonth = DateTime(clamped.year, clamped.month);
        }
      }
      if (widget.forDateOfBirth) {
        _dobStep = 1;
        _pickingYear = false;
      } else {
        _pickingYear = false;
      }
    });
  }

  void _applyMonth(int month) {
    final year = _focusedMonth.year;
    var day = _selectedDate.day;
    final maxDay = DateTime(year, month + 1, 0).day;
    if (day > maxDay) day = maxDay;
    final candidate = DateTime(year, month, day);
    setState(() {
      _focusedMonth = DateTime(year, month);
      if (_isSelectable(candidate)) {
        _selectedDate = candidate;
      }
      _dobStep = 2;
      _pickingYear = false;
    });
  }

  List<int> get _years {
    final years = <int>[];
    // Ascending for DOB (older → newer reads more naturally when scrolling
    // from a childhood decade); descending for scheduling.
    if (widget.forDateOfBirth) {
      for (var y = widget.firstDate.year; y <= widget.lastDate.year; y++) {
        years.add(y);
      }
    } else {
      for (var y = widget.lastDate.year; y >= widget.firstDate.year; y--) {
        years.add(y);
      }
    }
    return years;
  }

  List<int> get _decadeStarts {
    final starts = <int>[];
    final firstDecade = (widget.firstDate.year ~/ 10) * 10;
    final lastDecade = (widget.lastDate.year ~/ 10) * 10;
    for (var d = firstDecade; d <= lastDecade; d += 10) {
      starts.add(d);
    }
    return starts;
  }

  @override
  Widget build(BuildContext context) {
    final isDob = widget.forDateOfBirth;
    final headerFmt =
        DateFormat(isDob ? 'MMM d, yyyy' : 'EEE, MMM d');
    final age = DentalDatePickerDialog.ageInYears(_selectedDate);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: DentalDatePickerColors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 400,
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: DentalDatePickerColors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              offset: const Offset(0, 12),
              blurRadius: 24,
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: DentalDatePickerColors.muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        headerFmt.format(_selectedDate),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: DentalDatePickerColors.text,
                        ),
                      ),
                      if (isDob) ...[
                        const SizedBox(height: 4),
                        Text(
                          age == 1 ? 'Age 1 year' : 'Age $age years',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: DentalDatePickerColors.active,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: DentalDatePickerColors.active.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    color: DentalDatePickerColors.active,
                    size: 22,
                  ),
                ),
              ],
            ),
            if (isDob) ...[
              const SizedBox(height: 14),
              _DobStepBar(
                step: _dobStep,
                onStepTap: (step) {
                  setState(() {
                    _dobStep = step;
                    _pickingYear = step == 0;
                  });
                },
              ),
            ],
            if (widget.showQuickPresets) ...[
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _PresetChip(
                      label: 'Today',
                      selected: _isSameDay(_selectedDate, _today),
                      onTap: () => _selectPreset(0),
                    ),
                    const SizedBox(width: 8),
                    _PresetChip(
                      label: 'Tomorrow',
                      selected: _isSameDay(
                        _selectedDate,
                        _today.add(const Duration(days: 1)),
                      ),
                      onTap: () => _selectPreset(1),
                    ),
                    const SizedBox(width: 8),
                    _PresetChip(
                      label: 'In 1 Week',
                      selected: _isSameDay(
                        _selectedDate,
                        _today.add(const Duration(days: 7)),
                      ),
                      onTap: () => _selectPreset(7),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Divider(height: 1, color: DentalDatePickerColors.border),
            const SizedBox(height: 12),
            if (!isDob || _dobStep == 2)
              _MonthYearBar(
                monthLabel: _months[_focusedMonth.month - 1],
                year: _focusedMonth.year,
                pickingYear: _pickingYear,
                onPrev: () => _shiftMonth(-1),
                onNext: () => _shiftMonth(1),
                onToggleYear: () {
                  if (isDob) {
                    setState(() {
                      _dobStep = 0;
                      _pickingYear = true;
                    });
                  } else {
                    setState(() => _pickingYear = !_pickingYear);
                  }
                },
              ),
            if (isDob && _dobStep == 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Choose birth year',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: DentalDatePickerColors.muted,
                    ),
                  ),
                ),
              ),
            if (isDob && _dobStep == 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Choose birth month · ${_focusedMonth.year}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: DentalDatePickerColors.muted,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: isDob
                  ? _buildDobBody()
                  : (_pickingYear
                      ? _YearGrid(
                          key: const ValueKey('years'),
                          years: _years,
                          selectedYear: _focusedMonth.year,
                          decadeStarts: const [],
                          onSelect: _applyYear,
                        )
                      : _CalendarGrid(
                          key: ValueKey(
                            '${_focusedMonth.year}-${_focusedMonth.month}',
                          ),
                          focusedMonth: _focusedMonth,
                          selectedDate: _selectedDate,
                          today: _today,
                          isSelectable: _isSelectable,
                          onSelect: _selectDate,
                          weekdays: _weekdays,
                        )),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButtons.ghost(
                  onPressed: () => Navigator.of(context).pop(),
                  label: 'Cancel',
                ),
                const SizedBox(width: 8),
                AppButtons.primary(
                  onPressed: () => Navigator.of(context).pop(_selectedDate),
                  label: isDob ? 'Use this date' : 'Select Date',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDobBody() {
    switch (_dobStep) {
      case 0:
        return _YearGrid(
          key: const ValueKey('dob-years'),
          years: _years,
          selectedYear: _focusedMonth.year,
          decadeStarts: _decadeStarts,
          onSelect: _applyYear,
        );
      case 1:
        return _MonthGrid(
          key: ValueKey('dob-months-${_focusedMonth.year}'),
          year: _focusedMonth.year,
          selectedMonth: _focusedMonth.month,
          monthLabels: _monthShort,
          firstDate: widget.firstDate,
          lastDate: widget.lastDate,
          onSelect: _applyMonth,
        );
      default:
        return _CalendarGrid(
          key: ValueKey(
            '${_focusedMonth.year}-${_focusedMonth.month}',
          ),
          focusedMonth: _focusedMonth,
          selectedDate: _selectedDate,
          today: _today,
          isSelectable: _isSelectable,
          onSelect: _selectDate,
          weekdays: _weekdays,
        );
    }
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DobStepBar extends StatelessWidget {
  const _DobStepBar({
    required this.step,
    required this.onStepTap,
  });

  final int step;
  final ValueChanged<int> onStepTap;

  @override
  Widget build(BuildContext context) {
    const labels = ['Year', 'Month', 'Day'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: i <= step
                    ? DentalDatePickerColors.active.withValues(alpha: 0.35)
                    : DentalDatePickerColors.border,
              ),
            ),
          Material(
            color: i == step
                ? DentalDatePickerColors.active
                : i < step
                    ? DentalDatePickerColors.active.withValues(alpha: 0.12)
                    : DentalDatePickerColors.surface,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: () => onStepTap(i),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: i == step
                        ? Colors.white
                        : i < step
                            ? DentalDatePickerColors.active
                            : DentalDatePickerColors.muted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? DentalDatePickerColors.active.withValues(alpha: 0.12)
          : DentalDatePickerColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected
                  ? DentalDatePickerColors.active
                  : const Color(0xFF334155),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthYearBar extends StatelessWidget {
  const _MonthYearBar({
    required this.monthLabel,
    required this.year,
    required this.pickingYear,
    required this.onPrev,
    required this.onNext,
    required this.onToggleYear,
  });

  final String monthLabel;
  final int year;
  final bool pickingYear;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToggleYear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onPrev,
          tooltip: 'Previous month',
          icon: const Icon(Icons.chevron_left_rounded),
          color: DentalDatePickerColors.primary,
        ),
        Expanded(
          child: InkWell(
            onTap: onToggleYear,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$monthLabel $year',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: DentalDatePickerColors.text,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    pickingYear
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                    color: DentalDatePickerColors.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          tooltip: 'Next month',
          icon: const Icon(Icons.chevron_right_rounded),
          color: DentalDatePickerColors.primary,
        ),
      ],
    );
  }
}

class _YearGrid extends StatefulWidget {
  const _YearGrid({
    super.key,
    required this.years,
    required this.selectedYear,
    required this.onSelect,
    this.decadeStarts = const [],
  });

  final List<int> years;
  final int selectedYear;
  final ValueChanged<int> onSelect;
  final List<int> decadeStarts;

  @override
  State<_YearGrid> createState() => _YearGridState();
}

class _YearGridState extends State<_YearGrid> {
  final _controller = ScrollController();
  static const _rowExtent = 48.0; // approx cell + spacing

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  @override
  void didUpdateWidget(covariant _YearGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedYear != widget.selectedYear) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollToSelected({int? year}) {
    if (!_controller.hasClients) return;
    final target = year ?? widget.selectedYear;
    final index = widget.years.indexOf(target);
    if (index < 0) return;
    final row = index ~/ 4;
    final offset = (row * _rowExtent)
        .clamp(0.0, _controller.position.maxScrollExtent);
    _controller.jumpTo(offset);
  }

  void _jumpToDecade(int decadeStart) {
    for (final y in widget.years) {
      if (y >= decadeStart && y < decadeStart + 10) {
        _scrollToSelected(year: y);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      child: Column(
        children: [
          if (widget.decadeStarts.isNotEmpty) ...[
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.decadeStarts.length,
                separatorBuilder: (context, index) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final decade = widget.decadeStarts[i];
                  final inDecade = widget.selectedYear >= decade &&
                      widget.selectedYear < decade + 10;
                  return Material(
                    color: inDecade
                        ? DentalDatePickerColors.active.withValues(alpha: 0.12)
                        : DentalDatePickerColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: () => _jumpToDecade(decade),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Text(
                          '${decade}s',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: inDecade
                                ? DentalDatePickerColors.active
                                : DentalDatePickerColors.muted,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
          Expanded(
            child: GridView.builder(
              controller: _controller,
              padding: const EdgeInsets.symmetric(vertical: 4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.7,
              ),
              itemCount: widget.years.length,
              itemBuilder: (context, i) {
                final year = widget.years[i];
                final selected = year == widget.selectedYear;
                return Material(
                  color: selected
                      ? DentalDatePickerColors.active
                      : DentalDatePickerColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: () => widget.onSelect(year),
                    borderRadius: BorderRadius.circular(10),
                    child: Center(
                      child: Text(
                        '$year',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? Colors.white
                              : DentalDatePickerColors.text,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    super.key,
    required this.year,
    required this.selectedMonth,
    required this.monthLabels,
    required this.firstDate,
    required this.lastDate,
    required this.onSelect,
  });

  final int year;
  final int selectedMonth;
  final List<String> monthLabels;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<int> onSelect;

  bool _monthEnabled(int month) {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0);
    if (end.isBefore(firstDate) || start.isAfter(lastDate)) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.2,
        ),
        itemCount: 12,
        itemBuilder: (context, i) {
          final month = i + 1;
          final enabled = _monthEnabled(month);
          final selected = month == selectedMonth;
          return Material(
            color: !enabled
                ? DentalDatePickerColors.surface.withValues(alpha: 0.5)
                : selected
                    ? DentalDatePickerColors.active
                    : DentalDatePickerColors.surface,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: enabled ? () => onSelect(month) : null,
              borderRadius: BorderRadius.circular(10),
              child: Center(
                child: Text(
                  monthLabels[i],
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: !enabled
                        ? DentalDatePickerColors.muted.withValues(alpha: 0.45)
                        : selected
                            ? Colors.white
                            : DentalDatePickerColors.text,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    super.key,
    required this.focusedMonth,
    required this.selectedDate,
    required this.today,
    required this.isSelectable,
    required this.onSelect,
    required this.weekdays,
  });

  final DateTime focusedMonth;
  final DateTime selectedDate;
  final DateTime today;
  final bool Function(DateTime day) isSelectable;
  final ValueChanged<DateTime> onSelect;
  final List<String> weekdays;

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(focusedMonth.year, focusedMonth.month);
    // Monday-based week index (1=Mon … 7=Sun) → 0..6
    final leading = (firstOfMonth.weekday + 6) % 7;
    final daysInMonth =
        DateTime(focusedMonth.year, focusedMonth.month + 1, 0).day;
    final totalCells = ((leading + daysInMonth + 6) ~/ 7) * 7;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (final d in weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: DentalDatePickerColors.muted,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var row = 0; row < totalCells / 7; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _DayCell(
                      index: row * 7 + col,
                      leading: leading,
                      daysInMonth: daysInMonth,
                      focusedMonth: focusedMonth,
                      selectedDate: selectedDate,
                      today: today,
                      isSelectable: isSelectable,
                      onSelect: onSelect,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.index,
    required this.leading,
    required this.daysInMonth,
    required this.focusedMonth,
    required this.selectedDate,
    required this.today,
    required this.isSelectable,
    required this.onSelect,
  });

  final int index;
  final int leading;
  final int daysInMonth;
  final DateTime focusedMonth;
  final DateTime selectedDate;
  final DateTime today;
  final bool Function(DateTime day) isSelectable;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final dayNum = index - leading + 1;
    if (dayNum < 1 || dayNum > daysInMonth) {
      return const SizedBox(height: 40);
    }

    final date = DateTime(focusedMonth.year, focusedMonth.month, dayNum);
    final selectable = isSelectable(date);
    final selected = date.year == selectedDate.year &&
        date.month == selectedDate.month &&
        date.day == selectedDate.day;
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;

    Color bg = Colors.transparent;
    Color fg = DentalDatePickerColors.text;
    Border? border;

    if (!selectable) {
      fg = DentalDatePickerColors.text.withValues(alpha: 0.3);
    } else if (selected) {
      bg = DentalDatePickerColors.active;
      fg = Colors.white;
    } else if (isToday) {
      border = Border.all(color: DentalDatePickerColors.active, width: 1.5);
      fg = DentalDatePickerColors.active;
    }

    return SizedBox(
      height: 40,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: selectable ? () => onSelect(date) : null,
          customBorder: const CircleBorder(),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: border,
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: DentalDatePickerColors.active
                              .withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$dayNum',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: fg,
                      height: 1,
                    ),
                  ),
                  if (isToday && !selected)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: DentalDatePickerColors.active,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
