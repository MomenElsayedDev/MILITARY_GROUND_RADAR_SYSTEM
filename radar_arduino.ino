// ================================================================
//  MILITARY RADAR — Arduino MK-V
//  Fast + Sensitive version
//  HC-SR04 + SG90 Servo + LCD I2C + Buzzer
// ================================================================

#include <Servo.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>

LiquidCrystal_I2C lcd(0x27, 16, 2);

#define SERVO_PIN   2
#define TRIG_PIN    7
#define ECHO_PIN    6
#define BUZZER_PIN  8

Servo radarServo;

int   angle       = 0;
int   direction   = 1;
int   distance    = 0;

// ── LCD update throttle ──
// LCD بيأخد وقت — منحدثوش كل frame
unsigned long lastLCDUpdate = 0;
const int LCD_INTERVAL = 80;   // ms بين كل update للـ LCD

// ── Buzzer non-blocking ──
unsigned long buzzerOnTime = 0;
bool buzzerState = false;

// ── Alert threshold ──
const int ALERT_DIST = 30;     // cm

// ================================================================
void setup() {
  Serial.begin(115200);         // ← أسرع من 9600 بكتير

  pinMode(TRIG_PIN,   OUTPUT);
  pinMode(ECHO_PIN,   INPUT);
  pinMode(BUZZER_PIN, OUTPUT);

  radarServo.attach(SERVO_PIN);
  radarServo.write(0);

  lcd.init();
  lcd.backlight();
  lcd.setCursor(0, 0);
  lcd.print("  RADAR MK-V  ");
  lcd.setCursor(0, 1);
  lcd.print(" Initializing ");
  delay(1000);
  lcd.clear();
}

// ================================================================
void loop() {
  // ── Move servo one step ──
  radarServo.write(angle);

  // ── Single fast reading (no averaging = faster) ──
  distance = readDistanceFast();

  // ── Send to Processing immediately ──
  Serial.print(angle);
  Serial.print(",");
  Serial.println(distance);

  // ── Buzzer (non-blocking) ──
  handleBuzzer(distance);

  // ── LCD (throttled — not every frame) ──
  unsigned long now = millis();
  if (now - lastLCDUpdate >= LCD_INTERVAL) {
    updateLCD(angle, distance);
    lastLCDUpdate = now;
  }

  // ── Step angle ──
  angle += direction;
  if (angle >= 180) { angle = 180; direction = -1; }
  if (angle <= 0)   { angle = 0;   direction =  1; }

  // ── Minimum delay for servo to physically move ──
  // 3ms per degree is the minimum for SG90
  // No extra delay needed — the sensor reading takes ~3-5ms already
}

// ================================================================
// SINGLE FAST READING — no averaging, short timeout
// ================================================================
int readDistanceFast() {
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);

  // Timeout = 15000µs → max ~255cm (كافي ومش بيضيع وقت)
  long duration = pulseIn(ECHO_PIN, HIGH, 15000);

  if (duration == 0) return 0;

  int d = duration * 0.034 / 2;
  if (d > 400 || d < 1) return 0;
  return d;
}

// ================================================================
// NON-BLOCKING BUZZER
// بدل ما يعمل HIGH/LOW كل frame
// بيعمل beep قصير لما يكتشف
// ================================================================
void handleBuzzer(int dist) {
  unsigned long now = millis();

  if (dist > 0 && dist < ALERT_DIST) {
    if (!buzzerState) {
      digitalWrite(BUZZER_PIN, HIGH);
      buzzerState  = true;
      buzzerOnTime = now;
    }
  } else {
    if (buzzerState && now - buzzerOnTime >= 50) {
      digitalWrite(BUZZER_PIN, LOW);
      buzzerState = false;
    }
  }
}

// ================================================================
// LCD UPDATE — throttled
// ================================================================
void updateLCD(int ang, int dist) {
  // Row 0: Angle
  lcd.setCursor(0, 0);
  lcd.print("Ang:");
  lcd.print(ang);
  lcd.print((char)223);
  lcd.print("        ");   // clear old chars

  // Row 1: Distance
  lcd.setCursor(0, 1);
  if (dist > 0 && dist < 400) {
    lcd.print("Dist:");
    lcd.print(dist);
    lcd.print("cm   ");
  } else {
    lcd.print("No Object    ");
  }
}