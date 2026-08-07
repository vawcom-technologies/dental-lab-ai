import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Clinical design tokens for the dental date picker.
class DentalDatePickerColors {
  static const primary = Color(0xFF1E3A8A);
  static const active = Color(0xFF2563EB);
  static const surface = Color(0xFFF1F5F9);
  static const text = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const border = Color(0xFFE2E8F0);
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
    this.selectableDayPredicate,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;
  final bool showQuickPresets;
  final bool Function(DateTime day)? selectableDayPredicate;

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime get today => dateOnly(DateTime.now());

  /// Shows the clinical date picker and returns the chosen day (date-only).
  static Future<DateTime?> show({
    required BuildContext context,
    required DateTime initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
    String title = 'Select Date',
    bool showQuickPresets = true,
    bool Function(DateTime day)? selectableDayPredicate,
  }) {
    final first = dateOnly(firstDate ?? DateTime(1900));
    final last = dateOnly(lastDate ?? DateTime(2100));
    var initial = dateOnly(initialDate);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;

    return showDialog<DateTime>(
      context: context,
      barrierDismissible: true,
      builder: (context) => DentalDatePickerDialog(
        initialDate: initial,
        firstDate: first,
        lastDate: last,
        title: title,
        showQuickPresets: showQuickPresets,
        selectableDayPredicate: selectableDayPredicate,
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

  /// Patient date of birth — past dates only; opens on existing DOB or **today**
  /// (use the year grid to jump quickly, not a hardcoded ~30y offset).
  static Future<DateTime?> showForDateOfBirth({
    required BuildContext context,
    DateTime? currentDob,
    String title = 'Date of Birth',
  }) {
    final now = today;
    return show(
      context: context,
      initialDate: currentDob ?? now,
      firstDate: DateTime(1900),
      lastDate: now,
      title: title,
      showQuickPresets: false,
    );
  }

  @override
  State<DentalDatePickerDialog> createState() => _DentalDatePickerDialogState();
}

class _DentalDatePickerDialogState extends State<DentalDatePickerDialog> {
  late DateTime _selectedDate;
  late DateTime _focusedMonth;
  bool _pickingYear = false;

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

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _focusedMonth = DateTime(widget.initialDate.year, widget.initialDate.month);
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
    });
  }

  List<int> get _years {
    final years = <int>[];
    for (var y = widget.lastDate.year; y >= widget.firstDate.year; y--) {
      years.add(y);
    }
    return years;
  }

  @override
  Widget build(BuildContext context) {
    final headerFmt = DateFormat('EEE, MMM d');

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
            _MonthYearBar(
              monthLabel: _months[_focusedMonth.month - 1],
              year: _focusedMonth.year,
              pickingYear: _pickingYear,
              onPrev: () => _shiftMonth(-1),
              onNext: () => _shiftMonth(1),
              onToggleYear: () => setState(() => _pickingYear = !_pickingYear),
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _pickingYear
                  ? _YearGrid(
                      key: const ValueKey('years'),
                      years: _years,
                      selectedYear: _focusedMonth.year,
                      onSelect: (year) {
                        final month = _focusedMonth.month;
                        var day = _selectedDate.day;
                        final maxDay = DateTime(year, month + 1, 0).day;
                        if (day > maxDay) day = maxDay;
                        final candidate = DateTime(year, month, day);
                        setState(() {
                          _focusedMonth = DateTime(year, month);
                          if (_isSelectable(candidate)) {
                            _selectedDate = candidate;
                          }
                          _pickingYear = false;
                        });
                      },
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
                    ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: DentalDatePickerColors.muted,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_selectedDate),
                  style: FilledButton.styleFrom(
                    backgroundColor: DentalDatePickerColors.active,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Select Date',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
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

class _YearGrid extends StatelessWidget {
  const _YearGrid({
    super.key,
    required this.years,
    required this.selectedYear,
    required this.onSelect,
  });

  final List<int> years;
  final int selectedYear;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      child: GridView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.7,
        ),
        itemCount: years.length,
        itemBuilder: (context, i) {
          final year = years[i];
          final selected = year == selectedYear;
          return Material(
            color: selected
                ? DentalDatePickerColors.active
                : DentalDatePickerColors.surface,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () => onSelect(year),
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
