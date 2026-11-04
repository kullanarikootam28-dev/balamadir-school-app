import 'package:equatable/equatable.dart';

enum PaymentStatus { pending, paid, overdue, waived }

class FeePayment extends Equatable {
  const FeePayment({
    required this.id,
    required this.invoiceId,
    required this.studentId,
    required this.amountPaise,   // stored in paise (₹1 = 100 paise)
    required this.status,
    this.dueDate,
    this.paidAt,
    this.description,
    this.transactionRef,
    this.feeTypeId,
    this.paymentMode,
    this.receiptNumber,
  });

  final String id;
  final String invoiceId;      // human-readable invoice number
  final String studentId;      // FK → profiles.id
  final int amountPaise;       // ₹100 scale → store as paise
  final PaymentStatus status;
  final DateTime? dueDate;
  final DateTime? paidAt;
  final String? description;   // e.g. "Term 1 Tuition Fee"
  final String? transactionRef;
  final String? feeTypeId;     // FK → fee_types.id
  final String? paymentMode;   // 'Cash', 'UPI', 'Cheque', 'Bank Transfer', ...
  final String? receiptNumber;

  /// Display amount in rupees (₹).
  String get amountDisplay =>
      '₹${(amountPaise / 100).toStringAsFixed(2)}';

  factory FeePayment.fromJson(Map<String, dynamic> json) => FeePayment(
        id: json['id'] as String,
        invoiceId: json['invoice_id'] as String,
        studentId: json['student_id'] as String,
        amountPaise: json['amount_paise'] as int,
        status: PaymentStatus.values
            .firstWhere((s) => s.name == json['status']),
        dueDate: json['due_date'] != null
            ? DateTime.parse(json['due_date'] as String)
            : null,
        paidAt: json['paid_at'] != null
            ? DateTime.parse(json['paid_at'] as String)
            : null,
        description: json['description'] as String?,
        transactionRef: json['transaction_ref'] as String?,
        feeTypeId: json['fee_type_id'] as String?,
        paymentMode: json['payment_mode'] as String?,
        receiptNumber: json['receipt_number'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'invoice_id': invoiceId,
        'student_id': studentId,
        'amount_paise': amountPaise,
        'status': status.name,
        'due_date': dueDate?.toIso8601String().substring(0, 10),
        'description': description,
        'transaction_ref': transactionRef,
        'fee_type_id': feeTypeId,
        'payment_mode': paymentMode,
        'receipt_number': receiptNumber,
      };

  @override
  List<Object?> get props => [id, invoiceId, studentId];
}
