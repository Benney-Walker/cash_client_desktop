import 'package:flutter/material.dart';

import '../common/step_flow.dart';
import 'member_profile.dart';

// How member, ID and account statuses are shown. Every status is an icon
// and a label, never colour alone; green is kept for success.

StatusPill membershipPill(MembershipStatus status, {Key? key}) => StatusPill(
      key: key,
      label: status.label,
      tone: switch (status) {
        MembershipStatus.active => StatusTone.success,
        MembershipStatus.pending => StatusTone.warning,
        MembershipStatus.suspended => StatusTone.danger,
        MembershipStatus.inactive => StatusTone.neutral,
      },
    );

StatusPill kycPill(KycState state, {Key? key}) => StatusPill(
      key: key,
      label: state.label,
      tone: switch (state) {
        KycState.verified => StatusTone.success,
        KycState.rejected => StatusTone.danger,
        KycState.notSubmitted => StatusTone.warning,
        KycState.pending || KycState.manualReview => StatusTone.warning,
      },
      icon: state == KycState.notSubmitted ? Icons.badge_outlined : null,
    );

StatusPill accountPill(AccountState status) => StatusPill(
      label: status.label,
      tone: switch (status) {
        AccountState.active => StatusTone.success,
        AccountState.frozen => StatusTone.warning,
        AccountState.inactive || AccountState.closed => StatusTone.neutral,
      },
    );
