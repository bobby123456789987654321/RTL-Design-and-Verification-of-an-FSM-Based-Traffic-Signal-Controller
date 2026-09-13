# Traffic Light Controller — Verilog RTL on Cyclone V (DE1-SoC)

FSM-based two-way intersection controller with pedestrian walk phase,
all-red clearance intervals, and a seven-segment phase countdown.
Target: Terasic DE1-SoC, Cyclone V `5CSEMA5F31C6N`.

---

## Defects found and fixed

The first version of this design passed on-board demonstration. Building a
self-checking testbench afterwards exposed four functional defects that
visual inspection of waveforms had missed.

### 1. Off-by-one phase duration

The FSM counted up and transitioned on `timer == N`, which occupies `N+1`
tick intervals. A phase specified as 7 s ran for 8 s, and the countdown
displayed a trailing `0` for a full second.

Replaced with a down-counter loaded on state entry that transitions at
`sec_left == 1`. Phases now last exactly N seconds and the display runs
N..1 with no trailing zero.

### 2. Conflicting greens during the all-red interlock

Output logic drove raw `LEDR` bit patterns whose polarity contradicted the
pin table. Under the documented mapping the all-red states asserted **both**
green aspects — the exact condition the interlock exists to prevent.

Fixed structurally rather than by correcting the constant: outputs are now
named signals (`ns_g`, `ns_r`, …) that default to all-red, with only the
active direction lifted out of red. No case arm *can* assert two greens.

### 3. Pedestrian request starved vehicle traffic

The request was latched on **level** with set-priority, so holding the button
down re-armed it continuously and every interlock routed straight back into
the walk phase.

The button now passes through a two-flop synchroniser and a counter debouncer
that emits a **one-clock rising-edge pulse**. One press produces one request.

### 4. East–west direction skipped entirely

A single walk state always returned to `NS_GREEN`, so a pedestrian request
raised during the north–south phase skipped the east–west green completely.

Split into `WALK_1` (returns to EW) and `WALK_2` (returns to NS).

### Also addressed

- Buttons were sampled directly into logic with no synchroniser
  (metastability risk). Added `sync_2ff` and `reset_sync`.
- Reset was released asynchronously. Now async-assert / sync-deassert.
- The all-red clearance was an accidental single tick, not a designed value.
  Now the explicit parameter `T_ALLRED`.
- `DIV_MAX` was hard-coded, forcing 500,000,000 ns of simulation per second
  of behaviour. Now a parameter, overridden in the testbench.

---

## Verification

`tb/traffic_light_top_tb.v` is self-checking — it reports PASS/FAIL and an
error count rather than printing a console dump for a human to read.

**Every safety assertion checks the output pins, not internal FSM state.**
An assertion written against `state` would have missed defect #2 entirely,
because the state sequence was correct all along; only the output decode was
wrong.

| Assertion | Property |
|---|---|
| A1 | NS and EW greens are never simultaneously asserted |
| A2 | A direction never shows green and red together |
| A3 | WALK is asserted only when both directions are red |
| A4 | Exactly one aspect is lit per direction at all times |
| A5 | Countdown never exceeds the longest phase, never shows 0 |

Plus a phase-duration checker that measures every phase against its expected
length, and five directed tests: free-running cycles, a single clean press,
a bouncing press (random contact chatter), a button held for three full
cycles, and mid-cycle reset recovery.

### Mutation testing

To confirm the testbench is not vacuous, each original defect was
re-injected and the suite re-run:

| Injected defect | Caught by |
|---|---|
| Up-counting off-by-one | A5 (trailing zero) + duration checker |
| Raw-bit output decode | A1 (conflicting greens) |
| Level-sensitive request latch | T3 bounce test, T4 starvation test |

All three mutants fail. The clean design passes with 0 errors across
79 measured phases.

---

## Running the simulation

```bash
iverilog -g2012 -o sim.out rtl/*.v tb/traffic_light_top_tb.v
vvp sim.out
gtkwave tlc.vcd      # optional
```

Expected output:

```
=== Traffic Light Controller regression ===
T1  free-running cycles, no pedestrian request
T2  single clean press -> exactly one walk phase
T3  bouncing contacts -> still exactly one walk phase
T4  button held for 3 full cycles -> vehicles must not starve
T5  asynchronous reset returns to NS green

phases checked : 79
walk phases    : 3
RESULT : PASS  (0 errors)
```

---

## Synthesis

1. Quartus Prime Lite, device `5CSEMA5F31C6N`
2. Import `constraints/pins.qsf`
3. Settings → Timing Analyzer → add `constraints/traffic.sdc`
4. Processing → Start Compilation

Record from the Compilation Report, **Slow 1100mV 85C corner**:

| Metric | Where |
|---|---|
| ALMs, registers | Fitter → Resource Usage Summary |
| Fmax | Timing Analyzer → Fmax Summary |
| WNS / TNS | Timing Analyzer → Setup Summary |
| FSM encoding | Analysis & Synthesis → State Machines |

For the encoding comparison, recompile with
`STATE_MACHINE_PROCESSING` set to `"ONE-HOT"` and to `"MINIMAL BITS"`
and record both.

---

## Files

```
rtl/traffic_light_top.v   top level, I/O and instantiation
rtl/traffic_fsm.v         8-state Moore FSM, down-counter timing
rtl/clk_div.v             parameterised 1 Hz tick generator
rtl/debouncer.v           contact filter + rising-edge pulse
rtl/sync_2ff.v            two-flop input synchroniser
rtl/reset_sync.v          async assert, sync de-assert
rtl/seven_seg.v           HEX display decoder
tb/traffic_light_top_tb.v self-checking regression
constraints/traffic.sdc   timing constraints
constraints/pins.qsf      DE1-SoC pin assignments
```
