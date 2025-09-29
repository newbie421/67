// SPDX-License-Identifier: GPL-2.0-only
/*
 * Based on the x86 implementation.
 *
 * Copyright (C) 2012 ARM Ltd.
 * Author: Marc Zyngier <marc.zyngier@arm.com>
 */

#include <linux/perf_event.h>
#include <linux/kvm_host.h>

#include <asm/kvm_emulate.h>

/*
 * Static key used to advertise PMU availability in KVM.
 */
DEFINE_STATIC_KEY_FALSE(kvm_arm_pmu_available);

/*
 * Return nonzero if we are running inside a guest.
 */
static int kvm_is_in_guest(void)
{
	return kvm_get_running_vcpu() != NULL;
}

/*
 * Return nonzero if guest is running in user mode.
 */
static int kvm_is_user_mode(void)
{
	struct kvm_vcpu *vcpu;

	vcpu = kvm_get_running_vcpu();

	if (vcpu)
		return !vcpu_mode_priv(vcpu);

	return 0;
}

/*
 * Return guest instruction pointer.
 */
static unsigned long kvm_get_guest_ip(void)
{
	struct kvm_vcpu *vcpu;

	vcpu = kvm_get_running_vcpu();

	if (vcpu)
		return *vcpu_pc(vcpu);

	return 0;
}

/*
 * perf_guest_info_callbacks structure to hook KVM guest info
 * into the perf subsystem.
 */
static struct perf_guest_info_callbacks kvm_guest_cbs = {
	.is_in_guest	= kvm_is_in_guest,
	.is_user_mode	= kvm_is_user_mode,
	.get_guest_ip	= kvm_get_guest_ip,
};

/*
 * Initialize perf callbacks for KVM.
 */
int kvm_perf_init(void)
{
	/*
	 * Check if HW_PERF_EVENTS are supported by checking the number of
	 * hardware performance counters. This ensures that a physical PMU
	 * exists and CONFIG_PERF_EVENTS is enabled.
	 */
	if (IS_ENABLED(CONFIG_ARM_PMU) && perf_num_counters() > 0
				       && !is_protected_kvm_enabled())
		static_branch_enable(&kvm_arm_pmu_available);

	return perf_register_guest_info_callbacks(&kvm_guest_cbs);
}

/*
 * Unregister perf callbacks.
 */
int kvm_perf_teardown(void)
{
	return perf_unregister_guest_info_callbacks(&kvm_guest_cbs);
}
