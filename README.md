# 🛰️ MILITARY GROUND RADAR SYSTEM — MK-V

![logo](logo.jpg)

> **CLASSIFIED // ARDUINO + SG90 SERVO + HC-SR04 // 0°→180°→0° SWEEP**

A real-time radar visualization system built with Arduino and Processing. The hardware sweeps an ultrasonic sensor across a 180° arc and streams live distance data to a PC, where a full military-style HUD renders detected targets as persistent red dots on a radar scope — complete with CRT scanline effects, audio alerts, mini-map, compass rose, and a data recorder.

---

## 📦 Hardware Requirements

| Component | Spec | Notes |
|---|---|---|
| Arduino Uno | ATmega328P | Any Uno-compatible board works |
| SG90 Servo | 0°–180° | Mounted to sweep the sensor |
| HC-SR04 | Ultrasonic, 2–400 cm | Piggyback on servo horn |
| I²C LCD | 16×2, address `0x27` or `0x3F` | Shows live angle + distance |
| Buzzer | Active, 5V | Alerts when object < 30 cm |
| Jumper wires + breadboard | — | — |

### Wiring

```
Arduino Pin  →  Component
──────────────────────────
D2           →  Servo signal (orange)
D7           →  HC-SR04 TRIG
D6           →  HC-SR04 ECHO
D8           →  Buzzer +
A4 (SDA)     →  LCD SDA
A5 (SCL)     →  LCD SCL
5V / GND     →  Servo, HC-SR04, LCD, Buzzer power rails
```

---

## 💻 Software Requirements

### Arduino IDE
- **Library:** `LiquidCrystal_I2C` — install via Library Manager (`hd44780` or `Frank de Brabander` version)
- **Library:** `Servo.h` — built-in, no install needed

### Processing IDE (v3.x or 4.x)
- **Library:** `processing.serial.*` — bundled with Processing
- **Library:** `processing.sound.*` — install via `Sketch → Import Library → Add Library → Sound`

---

## 🚀 Quick Start

### 1 — Flash the Arduino

1. Open `radar_arduino.ino` in Arduino IDE
2. Select your board: **Tools → Board → Arduino Uno**
3. Select the correct port: **Tools → Port → COMx / /dev/ttyUSBx**
4. Click **Upload**

The LCD will display `Radar System / Initializing...` then begin showing live angle and distance readings.

### 2 — Launch the Processing Visualizer

1. Open `radar_display.pde` in Processing
2. Check the console output — it will list available serial ports
3. The sketch auto-connects to `ports[0]`. If your Arduino is on a different port, edit this line in `setup()`:
   ```java
   myPort = new Serial(this, ports[0], 9600);
   //                         ↑ change index, e.g. ports[1]
   ```
4. Click **Run (▶)**
5. Watch the boot sequence complete, then the live radar scope appears

> **No Arduino?** The visualizer runs in **SIM MODE** automatically — it shows the HUD with zero incoming data, which is useful for testing the UI.

---

## 🖥️ Visualizer Features

### Radar Scope
- **180° sweep** with a fading green trail showing recent sweep history
- **Red dots** mark detected targets at their exact angle + distance — they never move with the sweep line
- Dots fade gradually over **500 frames** if the target is no longer detected
- Each dot is labelled with a target ID (`T1`, `T2`, …) and distance in cm

### HUD Panels

| Panel | Location | Contents |
|---|---|---|
| System Status | Top-left | Azimuth, sweep direction, live dot count, total hits, closest-ever distance, uptime, sweep count, serial status, recorder state |
| Dot Log | Top-right | Per-target table: ID, azimuth, distance, age in frames; colour-coded by freshness |
| Proximity Bar | Bottom-centre | Smoothed proximity level; green → amber → red as object approaches |
| Mini-Map | Bottom-left | Scaled overhead view of all live dots |
| Compass Rose | Bottom-right | Rotating needle tracks sweep angle; cardinal labels |

### Alerts
- **Screen flash + text** when any object is within **8 cm**
- **Bell tone** (1200 Hz sine, envelope-shaped) on every new target detection; 80-frame cooldown prevents spam

### CRT Overlay
- Animated scanline
- Vignette edges
- Subtle flicker noise

---

## ⌨️ Keyboard Controls

| Key | Action |
|---|---|
| `R` | **Start / Stop recording** — streams angle+distance to memory; on stop, saves `radar_rec.csv` |
| `P` | **Start / Stop playback** — replays `radar_rec.csv` (loads from disk if memory is empty) |
| `C` | **Clear** all dots, reset hit counter and closest-distance stat |
| `+` | Increase playback speed (fewer delay frames) |
| `-` | Decrease playback speed (more delay frames) |

---

## 📡 Serial Protocol

The Arduino sends one CSV line per measurement at **9600 baud**:

```
<angle>,<distance>\n
```

**Examples:**
```
45,23
90,0
135,17
```

- `angle` — integer, 0–180 degrees
- `distance` — integer centimetres; `0` means no echo received within 20 ms timeout

The Processing sketch parses this in `serialEvent()` and updates `rawAngle` / `rawDist` each frame.

---

## ⚙️ Configuration Reference

### Arduino (`radar_arduino.ino`)

| Constant | Default | Description |
|---|---|---|
| `stepAngle` | `2` | Degrees per servo step — smaller = smoother but slower sweep |
| `delay(10)` | `10 ms` | Pause between steps — reduce for faster sweep |
| Buzzer threshold | `< 30 cm` | Distance at which buzzer activates |
| LCD alert range | `< 200 cm` | Below this shows distance; above shows "No Object" |
| Distance samples | `3` | Averaged readings per HC-SR04 measurement |

### Processing (`radar_display.pde`)

| Variable | Default | Description |
|---|---|---|
| `R` | `310 px` | Radar circle radius |
| `maxDist` | `40.0 cm` | Maximum mapped detection range |
| `TRAIL` | `120 frames` | Sweep trail length |
| `DOT_LIFE` | `500 frames` | Frames before an unconfirmed dot disappears |
| `MATCH_A` | `8.0°` | Angle threshold for "same target" matching |
| `MATCH_D` | `4.0 cm` | Distance threshold for "same target" matching |
| `MAX_DOTS` | `24` | Maximum simultaneous tracked targets |
| `BELL_CD_MAX` | `80 frames` | Minimum frames between bell sounds |

---

## 🗂️ File Structure

```
radar-mk5/
├──
|   └── logo.jpg
│   └── radar_arduino.ino     ← Arduino firmware
│   └── radar_display.pde     ← Processing visualizer
└── README.md
```

---

## 🔧 Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `Serial error` in Processing console | Wrong port index | Change `ports[0]` to the correct index |
| LCD shows garbage / nothing | Wrong I²C address | Try `0x3F` instead of `0x27`; use an I²C scanner sketch |
| Distance always 0 | TRIG/ECHO wiring | Check D7 → TRIG, D6 → ECHO; confirm 5V to HC-SR04 |
| Servo jitters | Insufficient current | Power servo from external 5V supply, share GND with Arduino |
| `Sound library not found` | Missing Processing library | `Sketch → Import Library → Add Library → search "Sound"` |
| Dots jump position | `MATCH_A`/`MATCH_D` too tight | Increase `MATCH_A` to 12° and `MATCH_D` to 6 cm |
| Sweep is too slow | `stepAngle` or `delay` | Increase `stepAngle` to 3–5 or reduce `delay()` to 5 ms |

---

## 📝 License

This project is released for educational and personal use. No warranty. Use responsibly.

---

*MILITARY GROUND RADAR SYSTEM MK-V — ALL SYSTEMS GO*