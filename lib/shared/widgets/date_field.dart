import 'package:flutter/material.dart';

String formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';

/// A read-only form field that opens a date picker on tap.
class DateField extends FormField<DateTime> {
  DateField({
    super.key,
    required String label,
    required DateTime firstDate,
    required DateTime lastDate,
    super.initialValue,
    super.validator,
    ValueChanged<DateTime>? onChanged,
    IconData icon = Icons.event_outlined,
  }) : super(
         builder: (state) {
           final value = state.value;
           return InkWell(
             borderRadius: BorderRadius.circular(4),
             onTap: () async {
               final picked = await showDatePicker(
                 context: state.context,
                 // The picker asserts the initial date is in range; a stored
                 // value may not be (an expired licence, say).
                 initialDate: _clamp(
                   value ?? DateTime.now(),
                   firstDate,
                   lastDate,
                 ),
                 firstDate: firstDate,
                 lastDate: lastDate,
               );
               if (picked == null) return;
               state.didChange(picked);
               onChanged?.call(picked);
             },
             child: InputDecorator(
               decoration: InputDecoration(
                 labelText: label,
                 prefixIcon: Icon(icon),
                 border: const OutlineInputBorder(),
                 errorText: state.errorText,
               ),
               isEmpty: value == null,
               child: Text(value == null ? '' : formatDate(value)),
             ),
           );
         },
       );

  static DateTime _clamp(DateTime date, DateTime min, DateTime max) =>
      date.isBefore(min) ? min : (date.isAfter(max) ? max : date);
}
