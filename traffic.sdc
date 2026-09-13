# ---------------------------------------------------------------------------
# traffic.sdc - timing constraints for the DE1-SoC traffic light controller
#
# Without an SDC file Quartus reports every path as unconstrained and there is
# no Fmax number at all. This file is what makes the Timing Analyzer produce
# the Fmax / WNS / slack figures worth putting on a CV.
#
# Add via: Assignments -> Settings -> Timing Analyzer -> add traffic.sdc
# ---------------------------------------------------------------------------

# ---- primary clock --------------------------------------------------------
# DE1-SoC CLOCK_50 = 50 MHz = 20.000 ns period
create_clock -name CLOCK_50 -period 20.000 [get_ports CLOCK_50]

# Model PLL/clock-tree jitter and uncertainty. Always call this after
# create_clock or the analysis is optimistic.
derive_clock_uncertainty

# ---- asynchronous inputs --------------------------------------------------
# KEY0 and KEY1 are mechanical push-buttons with no relationship to CLOCK_50.
# They are handled in RTL by reset_sync / sync_2ff, so there is no meaningful
# setup or hold requirement at the pin and the paths are cut.
#
# NOTE: cutting these is only legitimate BECAUSE the synchronisers exist.
# On the original design - which sampled the buttons directly - this would
# have been hiding a real metastability risk rather than documenting a
# handled one.
set_false_path -from [get_ports {KEY0 KEY1}]

# ---- outputs --------------------------------------------------------------
# LEDs and the seven-segment display drive human eyes, not a sampling device.
# There is no external setup/hold to meet, so these are cut as well.
set_false_path -to [get_ports {LEDR[*]}]
set_false_path -to [get_ports {HEX0[*]}]

# ---- cross-synchroniser paths ---------------------------------------------
# Prevent the fitter from trying to time the first stage of each synchroniser
# against the source domain. The (* preserve *) attribute in RTL stops these
# flops being merged; this stops them being falsely reported.
set_false_path -to [get_registers {*sync_2ff*sync[0]}]
set_false_path -to [get_registers {*reset_sync*sync[0]}]
