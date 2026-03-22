#include <Servo.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>

// LCD (address 0x27 or 0x3F)
LiquidCrystal_I2C lcd(0x27, 16, 2);

// Pins
#define SERVO_PIN 2
#define TRIG_PIN 7
#define ECHO_PIN 6
#define BUZZER_PIN 8

Servo radarServo;

int angle = 0;
int stepAngle = 2;

int distance = 0;

// ─────────────────────────────
void setup() {
  Serial.begin(9600);

  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  pinMode(BUZZER_PIN, OUTPUT);

  radarServo.attach(SERVO_PIN);

  // LCD Init
  lcd.init();
  lcd.backlight();

  lcd.setCursor(0, 0);
  lcd.print("Radar System");
  lcd.setCursor(0, 1);
  lcd.print("Initializing...");
  delay(1500);
  lcd.clear();
}

// ─────────────────────────────
void loop() {

  // Sweep forward
  for (angle = 0; angle <= 180; angle += stepAngle) {
    updateRadar();
  }

  // Sweep backward
  for (angle = 180; angle >= 0; angle -= stepAngle) {
    updateRadar();
  }
}

// ─────────────────────────────
void updateRadar() {
  radarServo.write(angle);

  distance = readDistance();

  sendData(angle, distance);
  buzzerAlert(distance);
  updateLCD(angle, distance);

  delay(10); // سرعة عالية
}

// ─────────────────────────────
int readDistance() {
  int sum = 0;
  int count = 3;

  for (int i = 0; i < count; i++) {
    digitalWrite(TRIG_PIN, LOW);
    delayMicroseconds(2);

    digitalWrite(TRIG_PIN, HIGH);
    delayMicroseconds(10);
    digitalWrite(TRIG_PIN, LOW);

    long duration = pulseIn(ECHO_PIN, HIGH, 20000);
    int d = duration * 0.034 / 2;

    if (d > 0 && d < 400) sum += d;
  }

  return sum / count;
}

// ─────────────────────────────
void sendData(int angle, int distance) {
  Serial.print(angle);
  Serial.print(",");
  Serial.println(distance);
}

// ─────────────────────────────
void buzzerAlert(int distance) {
  if (distance > 0 && distance < 30) {
    digitalWrite(BUZZER_PIN, HIGH);
  } else {
    digitalWrite(BUZZER_PIN, LOW);
  }
}

// ─────────────────────────────
void updateLCD(int angle, int distance) {

  lcd.setCursor(0, 0);
  lcd.print("Angle:");
  lcd.print(angle);
  lcd.print((char)223); // degree symbol
  lcd.print("   "); // clear extra chars

  lcd.setCursor(0, 1);

  if (distance > 0 && distance < 200) {
    lcd.print("Distance:");
    lcd.print(distance);
    lcd.print(" cm   ");
  } else {
    lcd.print("No Object   ");
  }
}