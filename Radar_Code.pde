// ================================================================
//  MILITARY GROUND RADAR SYSTEM — MK-V
//  Hardware : Arduino Uno + SG90 Servo + HC-SR04 Ultrasonic
//
//  CORE LOGIC v5 (FINAL FIX):
//    - Sweep line is 100% independent — just shows where servo points
//    - When HC-SR04 detects an object → red dot appears at that position
//    - Red dot stays at its fixed angle/distance — never moves with sweep
//    - Dot fades gradually after TGT_LIFE frames if not re-detected
//    - Bell sound on first detection of a new target
// ================================================================

import processing.serial.*;
import processing.sound.*;

// ================================================================
// COLOURS
// ================================================================
color C_BG       = color(3, 10, 6);
color C_HUD      = color(0, 210, 90);
color C_HUD_DIM  = color(0, 140, 60, 180);
color C_DOT      = color(255, 40, 40);       // red dot
color C_DOT_GLOW = color(255, 80, 80);
color C_SWEEP    = color(0, 255, 100);
color C_ALERT    = color(255, 30, 30);
color C_WARN     = color(255, 160, 0);
color C_COLD     = color(0, 220, 120);

// ================================================================
// SERIAL
// ================================================================
Serial  myPort;
boolean serialReady = false;

// ================================================================
// RAW DATA from Arduino  (angle + distance every frame)
// ================================================================
float rawAngle = 0;
float rawDist  = 0;

// ================================================================
// SMOOTHED SWEEP ANGLE  (for smooth visual animation only)
// ================================================================
float smoothAngle = 0;

// ================================================================
// RADAR GEOMETRY
// ================================================================
float R       = 310;   // radar radius in pixels
float maxDist = 40.0;  // max detection range in cm
int   cx, cy;          // radar centre on screen

// ================================================================
// SWEEP TRAIL  (ring buffer of recent sweep angles)
// ================================================================
int     TRAIL       = 120;
float[] sweepAngles = new float[TRAIL];

// ================================================================
// SWEEP DIRECTION  (+1 = going 0→180,  -1 = going 180→0)
// ================================================================
float prevRawAngle = 0;
int   sweepDir     = 1;
int   sweepCount   = 0;

// ================================================================
// RED DOTS  (detected targets)
//
//  Each dot has:
//    dotA[]  — fixed angle  (set once at detection, NEVER changes)
//    dotD[]  — fixed distance (set once at detection, NEVER changes)
//    dotAge[]— frames since last time this dot was confirmed
//    dotID[] — unique ID for log
//
//  A dot is drawn at (dotA[i], dotD[i]) always — even while the
//  sweep is somewhere else entirely.
// ================================================================
int   MAX_DOTS  = 24;
int   DOT_LIFE  = 500;      // frames before dot fades out
float MATCH_A   = 8.0;      // deg  — "same target" threshold
float MATCH_D   = 4.0;      // cm   — "same target" threshold

float[] dotA    = new float[MAX_DOTS];
float[] dotD    = new float[MAX_DOTS];
int[]   dotAge  = new int[MAX_DOTS];
int[]   dotID   = new int[MAX_DOTS];
int     dotCount = 0;
int     nextID   = 1;

// ================================================================
// STATISTICS
// ================================================================
int   systemUptime    = 0;
int   totalDetections = 0;
float closestEver     = 9999;

// ================================================================
// PROXIMITY LEVEL  (smoothed, for the bar)
// ================================================================
float smoothLevel = 0;

// ================================================================
// SOUND
// ================================================================
SinOsc  bellOsc;
Env     bellEnv;
float   bellCooldown = 0;
float   BELL_CD_MAX  = 80;

// ================================================================
// STATIC LAYER  (grid — drawn once)
// ================================================================
PGraphics staticLayer;

// ================================================================
// BOOT
// ================================================================
int     bootFrame = 0;
int     BOOT_LEN  = 140;
boolean booted    = false;

// ================================================================
// CRT FX
// ================================================================
float scanLine = 0;
float noiseOff = 0;

// ================================================================
// RECORDING
// ================================================================
boolean           recording  = false;
boolean           playback   = false;
ArrayList<String> recBuffer  = new ArrayList<String>();
int     playPtr    = 0;
int     playDelay  = 0;
int     PLAY_SPEED = 2;
PrintWriter recFile;

// ================================================================
// MINI-MAP + COMPASS
// ================================================================
float mmX, mmY, mmR;
float compassX, compassY;
PGraphics compassLayer;

// ================================================================
// SETUP
// ================================================================
void setup() {
  size(1280, 720, P2D);
  smooth(8);
  frameRate(60);

  cx = width / 2;
  cy = height - 30;

  mmX      = 80;
  mmY      = height - 130;
  mmR      = 80;
  compassX = width - 100;
  compassY = height - 110;

  // Init arrays
  for (int i = 0; i < TRAIL;    i++) sweepAngles[i] = -1;
  for (int i = 0; i < MAX_DOTS; i++) dotAge[i] = DOT_LIFE + 1;

  // Build layers
  staticLayer  = createGraphics(width, height, P2D);
  compassLayer = createGraphics(200, 200, P2D);
  buildStaticLayer();
  buildCompassLayer();

  // Sound
  bellOsc = new SinOsc(this);
  bellEnv = new Env(this);
  bellOsc.play();
  bellOsc.amp(0);

  // Serial
  String[] ports = Serial.list();
  printArray(ports);
  if (ports.length > 0) {
    try {
      myPort = new Serial(this, ports[0], 9600);
      myPort.bufferUntil('\n');
      serialReady = true;
    } catch (Exception e) {
      println("Serial error: " + e.getMessage());
    }
  }
}

// ================================================================
// MAIN LOOP
// ================================================================
void draw() {
  systemUptime++;

  // Boot screen
  if (!booted) {
    drawBootScreen();
    bootFrame++;
    if (bootFrame >= BOOT_LEN) booted = true;
    return;
  }

  // Playback data source
  if (playback) feedPlayback();

  // ── Track sweep direction ──
  float dA = rawAngle - prevRawAngle;
  if      (dA >  2) sweepDir = 1;
  else if (dA < -2) sweepDir = -1;
  prevRawAngle = rawAngle;

  // ── Smooth sweep angle (visual only) ──
  smoothAngle = lerpAngle(smoothAngle, rawAngle, 0.22);

  // ── Proximity level (for bar) ──
  float lv  = (rawDist > 0 && rawDist < maxDist) ? 1.0 - (rawDist / maxDist) : 0;
  smoothLevel = lerp(smoothLevel, lv, 0.08);

  // ── Register detection if distance is valid ──
  if (rawDist >= 1 && rawDist < maxDist) {
    registerDot(rawAngle, rawDist);
  }

  // ── Age all dots ──
  for (int i = 0; i < dotCount; i++) dotAge[i]++;
  removeDeadDots();

  // ── Update sounds & recording ──
  if (bellCooldown > 0) bellCooldown--;
  if (recording) recBuffer.add(nf(rawAngle,0,2)+","+nf(rawDist,0,2));

  // ── Render ──
  background(C_BG);
  image(staticLayer, 0, 0);

  pushMatrix();
  translate(cx, cy);
    drawSweepTrail();   // sweep line only — completely independent of dots
    drawRedDots();      // all detected dots at their fixed positions
  popMatrix();

  drawScanlineOverlay();
  drawHUD();
  drawDotLog();
  drawProximityBar();
  drawMiniMap();
  drawCompassRose();
  drawAlerts();
  drawRecordingIndicator();

  // Advance sweep trail buffer
  for (int i = TRAIL - 1; i > 0; i--) sweepAngles[i] = sweepAngles[i-1];
  sweepAngles[0] = smoothAngle;

  noiseOff += 0.008;
  scanLine  = (scanLine + 1.2) % height;
}

// ================================================================
// REGISTER A DOT
//   - If a dot already exists near this angle+distance → refresh it
//   - Otherwise create a new dot at the exact detected position
//   - The dot position is set ONCE and never changed after that
//     (except when the sweep passes again and confirms same position)
// ================================================================
void registerDot(float a, float d) {
  for (int i = 0; i < dotCount; i++) {
    float da = abs(dotA[i] - a);
    float dd = abs(dotD[i] - d);
    if (da < MATCH_A && dd < MATCH_D) {
      // Same target — just reset age (position stays fixed)
      dotAge[i] = 0;
      return;
    }
  }

  // New dot
  if (dotCount < MAX_DOTS) {
    dotA[dotCount]   = a;        // fixed angle
    dotD[dotCount]   = d;        // fixed distance
    dotAge[dotCount] = 0;
    dotID[dotCount]  = nextID++;
    dotCount++;
    totalDetections++;
    if (d < closestEver) closestEver = d;
    triggerBell();
  }
}

void removeDeadDots() {
  for (int i = dotCount - 1; i >= 0; i--) {
    if (dotAge[i] > DOT_LIFE) {
      for (int j = i; j < dotCount - 1; j++) {
        dotA[j]   = dotA[j+1];
        dotD[j]   = dotD[j+1];
        dotAge[j] = dotAge[j+1];
        dotID[j]  = dotID[j+1];
      }
      dotCount--;
    }
  }
}

// ================================================================
// SWEEP TRAIL  — pure sweep, no dots attached
// ================================================================
void drawSweepTrail() {
  // Fading trail
  for (int i = 0; i < TRAIL; i++) {
    if (sweepAngles[i] < 0) continue;
    float t = 1.0 - (float)i / TRAIL;
    stroke(0, 255, 100, t * t * 150);
    strokeWeight(map(t, 0, 1, 0.3, 3.5));
    float x = R * cos(radians(sweepAngles[i]));
    float y = -R * sin(radians(sweepAngles[i]));
    line(0, 0, x, y);
  }

  // Leading edge — bright glow
  for (int w = 5; w >= 1; w--) {
    stroke(0, 255, 120, w == 1 ? 255 : 30 * w);
    strokeWeight(w);
    float sx = R * cos(radians(smoothAngle));
    float sy = -R * sin(radians(smoothAngle));
    line(0, 0, sx, sy);
  }
}

// ================================================================
// RED DOTS
//   Position = dotA[i], dotD[i]  — completely fixed
//   The sweep angle is NOT used here at all
// ================================================================
void drawRedDots() {
  for (int i = 0; i < dotCount; i++) {
    float fade  = 1.0 - (float)dotAge[i] / DOT_LIFE;
    if (fade <= 0) continue;

    // ── Fixed position ──
    float r = map(dotD[i], 0, maxDist, 0, R);
    float x = r * cos(radians(dotA[i]));    // dotA[i] — never smoothAngle
    float y = -r * sin(radians(dotA[i]));   // dotA[i] — never smoothAngle

    float pulse = 0.5 + 0.5 * sin(frameCount * 0.18 + i * 0.7);

    // Outer glow
    noStroke();
    fill(255, 30, 30, 25 * fade);
    ellipse(x, y, 50 + pulse * 14, 50 + pulse * 14);

    // Inner glow
    fill(255, 60, 60, 55 * fade);
    ellipse(x, y, 22 + pulse * 6, 22 + pulse * 6);

    // Red dot (core)
    fill(255, 40, 40, 230 * fade);
    ellipse(x, y, 12, 12);

    // Bright white centre
    fill(255, 255, 255, 200 * fade);
    ellipse(x, y, 4, 4);

    // Label
    fill(255, 80, 80, fade * 210);
    noStroke();
    textSize(8);
    textAlign(LEFT);
    text("T" + dotID[i], x + 10, y - 4);
    fill(255, 180, 180, fade * 160);
    textSize(7);
    text(nf(dotD[i], 0, 1) + "cm", x + 10, y + 7);
  }
}

// ================================================================
// STATIC RADAR GRID
// ================================================================
void buildStaticLayer() {
  staticLayer.beginDraw();
  staticLayer.background(C_BG);
  staticLayer.translate(cx, cy);
  staticLayer.smooth(8);

  // Range rings
  for (int i = 1; i <= 8; i++) {
    float r   = R * i / 8;
    float dst = maxDist * i / 8;
    staticLayer.stroke(0, 130 - i*8, 50, 100);
    staticLayer.strokeWeight(0.8);
    staticLayer.noFill();
    staticLayer.arc(0, 0, r*2, r*2, PI, TWO_PI);
    staticLayer.fill(0, 160, 60, 130);
    staticLayer.textSize(8);
    staticLayer.textAlign(CENTER);
    staticLayer.text(nf(dst, 0, 0) + "cm", -r - 2, -5);
  }

  // Radial spokes every 10°
  for (int a = 0; a <= 180; a += 10) {
    float x = R * cos(radians(a));
    float y = -R * sin(radians(a));
    if (a % 30 == 0) {
      staticLayer.stroke(0, 130, 55, 100);
      staticLayer.strokeWeight(1.0);
    } else {
      staticLayer.stroke(0, 80, 35, 55);
      staticLayer.strokeWeight(0.5);
    }
    staticLayer.line(0, 0, x, y);
    if (a % 30 == 0) {
      staticLayer.fill(0, 160, 65, 150);
      staticLayer.textSize(9);
      staticLayer.textAlign(CENTER);
      float lx = (R+18)*cos(radians(a));
      float ly = -(R+18)*sin(radians(a));
      staticLayer.text(a + "°", lx, ly+3);
    }
  }

  // Centre crosshair + baseline
  staticLayer.stroke(0, 200, 80, 140);
  staticLayer.strokeWeight(1);
  staticLayer.line(-16, 0, 16, 0);
  staticLayer.line(0, -16, 0, 4);
  staticLayer.stroke(0, 160, 60, 120);
  staticLayer.strokeWeight(1.2);
  staticLayer.line(-R-20, 0, R+20, 0);

  staticLayer.endDraw();
}

// ================================================================
// COMPASS LAYER
// ================================================================
void buildCompassLayer() {
  compassLayer.beginDraw();
  compassLayer.background(0, 0);
  compassLayer.translate(100, 100);
  compassLayer.smooth(8);

  int cR = 70;
  compassLayer.stroke(0, 160, 60, 180);
  compassLayer.strokeWeight(1.5);
  compassLayer.noFill();
  compassLayer.ellipse(0, 0, cR*2, cR*2);

  String[] cardinals = {"N","NE","E","SE","S","SW","W","NW"};
  for (int i = 0; i < 8; i++) {
    float ang = radians(i*45 - 90);
    compassLayer.stroke(0, 200, 80, 200);
    compassLayer.strokeWeight(i%2==0 ? 1.5 : 0.8);
    compassLayer.line((cR-10)*cos(ang),(cR-10)*sin(ang),cR*cos(ang),cR*sin(ang));
    compassLayer.fill(0, 200, 80, 200);
    compassLayer.textSize(i%2==0 ? 10 : 7);
    compassLayer.textAlign(CENTER, CENTER);
    compassLayer.text(cardinals[i],(cR+12)*cos(ang),(cR+12)*sin(ang));
  }
  for (int i = 0; i < 24; i++) {
    if (i%3!=0) {
      float ang = radians(i*15 - 90);
      compassLayer.stroke(0, 120, 50, 120);
      compassLayer.strokeWeight(0.5);
      compassLayer.line((cR-5)*cos(ang),(cR-5)*sin(ang),cR*cos(ang),cR*sin(ang));
    }
  }
  compassLayer.noStroke();
  compassLayer.fill(0, 255, 100, 200);
  compassLayer.ellipse(0, 0, 5, 5);
  compassLayer.endDraw();
}

// ================================================================
// BOOT SCREEN
// ================================================================
void drawBootScreen() {
  background(0);
  float p = (float)bootFrame / BOOT_LEN;

  textAlign(CENTER);
  if (bootFrame > 10) {
    fill(0, 255, 100);
    textSize(16);
    text("MILITARY GROUND RADAR — MK-V", width/2, 90);
    fill(0, 180, 60);
    textSize(10);
    text("CLASSIFIED  //  ARDUINO + SG90 SERVO + HC-SR04  //  0°→180°→0°", width/2, 114);
  }

  String[] lines = {
    "POWER ON SELF-TEST......................",
    "SERVO SWEEP RANGE 0-180° CONFIRMED.....",
    "ULTRASONIC MODULE ONLINE................",
    "SERIAL LINK.............................",
    "TARGET DOT ENGINE.......................",
    "SWEEP ↔ DOTS: FULLY DECOUPLED..........",
    "THREAT ASSESSMENT ARMED.................",
    "DATA RECORDER STANDBY...................",
    "AUDIO BELL SYSTEM READY.................",
    "CRT OVERLAY ACTIVE......................",
    "MINI-MAP + COMPASS READY................",
    ">>> ALL SYSTEMS GO — SCANNING <<<"
  };
  String[] status = {
    "OK","OK","ONLINE",
    serialReady?"CONNECTED":"SIM MODE",
    "ARMED","CONFIRMED","ARMED",
    "STANDBY","READY","ACTIVE","READY",""
  };

  for (int i = 0; i < lines.length; i++) {
    int trigger = 8 + i*10;
    if (bootFrame > trigger) {
      float fade = min(1.0,(bootFrame-trigger)/8.0);
      if (i == lines.length-1) fill(0, 255, 120, fade*255);
      else fill(0, 200, 80, fade*220);
      textSize(11);
      text(lines[i]+" "+status[i], width/2, 158 + i*24);
    }
  }

  stroke(0, 200, 70);
  strokeWeight(1);
  noFill();
  rect(width/2-200, height-60, 400, 14, 4);
  noStroke();
  fill(0, 230, 80);
  rect(width/2-200, height-60, 400*p, 14, 4);
  fill(0, 180, 60);
  textSize(9);
  textAlign(CENTER);
  text(int(p*100)+"%", width/2, height-40);
}

// ================================================================
// HUD (left panel)
// ================================================================
void drawHUD() {
  float px = 10, py = 12;
  float pw = 205, ph = 300;

  fill(0, 18, 9, 210);
  noStroke();
  rect(px, py, pw, ph, 4);
  stroke(0, 140, 55, 140);
  strokeWeight(0.8);
  noFill();
  rect(px, py, pw, ph, 4);

  fill(0, 220, 90);
  textSize(10);
  textAlign(LEFT);
  text("╔ SYSTEM STATUS ╗", px+8, py+16);

  // Sweep direction arrow
  fill(sweepDir > 0 ? C_COLD : C_WARN);
  textSize(10);
  textAlign(RIGHT);
  text(sweepDir > 0 ? "0°→180° →" : "← 180°→0°", px+pw-8, py+16);

  int secs = systemUptime / 60;
  int mins = secs / 60; secs = secs % 60;

  String[] lbl = {
    "AZM","DIRECTION","DOTS LIVE","TOTAL HITS",
    "CLOSEST","UPTIME","SWEEPS","SERIAL","REC"
  };
  String[] val = {
    nf(smoothAngle, 3, 1) + "°",
    sweepDir > 0 ? "0 → 180" : "180 → 0",
    str(dotCount),
    str(totalDetections),
    closestEver < 9999 ? nf(closestEver, 2, 1) + " cm" : "---",
    nf(mins, 2) + ":" + nf(secs, 2),
    str(sweepCount),
    serialReady ? "ONLINE" : "SIM",
    recording ? "REC ●" : (playback ? "PLAY ▶" : "IDLE")
  };

  for (int i = 0; i < lbl.length; i++) {
    float ry = py + 34 + i * 28;
    fill(C_HUD_DIM);
    textSize(9);
    textAlign(LEFT);
    text(lbl[i], px+10, ry);
    fill(C_HUD);
    textSize(11);
    textAlign(RIGHT);
    text(val[i], px+pw-10, ry);
    stroke(0, 80, 35, 60);
    strokeWeight(0.4);
    line(px+8, ry+8, px+pw-8, ry+8);
  }
}

// ================================================================
// DOT LOG (right panel)
// ================================================================
void drawDotLog() {
  float px = width-238, py = 12;
  float pw = 226, ph = 380;

  fill(0, 18, 9, 210);
  noStroke();
  rect(px, py, pw, ph, 4);
  stroke(0, 140, 55, 140);
  strokeWeight(0.8);
  noFill();
  rect(px, py, pw, ph, 4);

  fill(0, 220, 90);
  textSize(10);
  textAlign(LEFT);
  text("╔ DOT LOG ╗", px+8, py+16);

  fill(C_HUD_DIM);
  textSize(8);
  text("ID     AZM      DIST     AGE", px+8, py+30);
  stroke(0, 100, 45, 100);
  line(px+6, py+33, px+pw-6, py+33);

  for (int i = 0; i < dotCount; i++) {
    float fade = 1.0 - (float)dotAge[i] / DOT_LIFE;
    if (fade <= 0) continue;

    // Colour based on age
    float r, g, b;
    if (fade > 0.7)      { r=255; g=80;  b=80;  }
    else if (fade > 0.3) { r=255; g=160; b=0;   }
    else                 { r=0;   g=180; b=80;  }

    fill(r, g, b, fade * 220);
    textSize(9);
    String row = "T" + nf(dotID[i], 2)
               + "   " + nf(dotA[i], 3, 0) + "°"
               + "   " + nf(dotD[i], 2, 1) + "cm"
               + "   " + dotAge[i];
    text(row, px+8, py+46 + i*17);
  }

  if (dotCount == 0) {
    fill(C_HUD_DIM);
    textSize(9);
    textAlign(CENTER);
    text("NO TARGETS DETECTED", px+pw/2, py+80);
    textAlign(LEFT);
  }

  fill(C_HUD_DIM);
  textSize(8);
  text("[R] Rec  [P] Play  [C] Clear", px+6, py+ph-10);
}

// ================================================================
// PROXIMITY BAR (bottom centre)
// ================================================================
void drawProximityBar() {
  float bw = 280, bh = 14;
  float bx = width/2 - bw/2;
  float by = height - 22;

  noFill();
  stroke(0, 180, 70, 160);
  strokeWeight(1);
  rect(bx, by, bw, bh, 5);

  noStroke();
  float lv = constrain(smoothLevel, 0, 1);
  if      (lv > 0.75) fill(C_ALERT);
  else if (lv > 0.45) fill(C_WARN);
  else                fill(C_COLD);
  rect(bx, by, bw * lv, bh, 5);

  fill(C_HUD_DIM);
  textAlign(CENTER);
  textSize(8);
  text("PROXIMITY", width/2, by-3);
}

// ================================================================
// MINI-MAP (bottom left)
// ================================================================
void drawMiniMap() {
  float px = mmX, py = mmY, r = mmR;

  fill(0, 15, 8, 210);
  noStroke();
  ellipse(px, py, r*2+16, r*2+16);
  stroke(0, 130, 50, 150);
  strokeWeight(1);
  noFill();
  ellipse(px, py, r*2+16, r*2+16);

  for (int i = 1; i <= 3; i++) {
    stroke(0, 90, 40, 80);
    strokeWeight(0.5);
    ellipse(px, py, r*2*i/3, r*2*i/3);
  }
  stroke(0, 100, 45, 80);
  line(px-r, py, px+r, py);
  line(px, py-r, px, py+r);

  // Sweep needle
  stroke(0, 200, 80, 120);
  strokeWeight(1.5);
  line(px, py,
       px + (r-4)*cos(radians(smoothAngle)),
       py - (r-4)*sin(radians(smoothAngle)));

  // Dots at their fixed positions
  for (int i = 0; i < dotCount; i++) {
    float fade = 1.0 - (float)dotAge[i] / DOT_LIFE;
    if (fade <= 0) continue;
    float mr = map(dotD[i], 0, maxDist, 0, r-6);
    float mx = px + mr * cos(radians(dotA[i]));
    float my = py - mr * sin(radians(dotA[i]));
    noStroke();
    fill(255, 50, 50, fade * 200);
    ellipse(mx, my, 5, 5);
  }

  fill(C_HUD_DIM);
  textSize(8);
  textAlign(CENTER);
  text("MINI-MAP", px, py+r+16);
}

// ================================================================
// COMPASS ROSE
// ================================================================
void drawCompassRose() {
  float px = compassX, py = compassY;
  int cr = 70;

  fill(0, 15, 8, 200);
  noStroke();
  ellipse(px, py, cr*2+20, cr*2+20);
  image(compassLayer, px-100, py-100, 200, 200);

  pushMatrix();
  translate(px, py);
  rotate(radians(-smoothAngle));
  stroke(0, 255, 100, 220);
  strokeWeight(2);
  fill(0, 255, 100, 200);
  triangle(0, -(cr-12), -5, 0, 5, 0);
  fill(255, 50, 50, 200);
  triangle(0,  (cr-12), -5, 0, 5, 0);
  popMatrix();

  noStroke();
  fill(0, 200, 80, 220);
  ellipse(px, py, 6, 6);

  fill(C_HUD_DIM);
  textSize(8);
  textAlign(CENTER);
  text("COMPASS", px, py+cr+18);
  fill(C_HUD);
  textSize(9);
  text(int(smoothAngle)+"°", px, py+cr+29);
}

// ================================================================
// ALERTS
// ================================================================
void drawAlerts() {
  // Proximity flash
  if (rawDist >= 1 && rawDist < 8) {
    float blink = (sin(frameCount * 0.35) > 0) ? 255 : 0;
    noStroke();
    fill(255, 0, 0, blink * 0.3);
    rect(0, 0, width, height);
    fill(255, 0, 0, blink);
    textAlign(CENTER);
    textSize(18);
    text("!! PROXIMITY ALERT — " + nf(rawDist,1,1) + " cm !!", width/2, height/2);
  }
}

// ================================================================
// CRT SCANLINE OVERLAY
// ================================================================
void drawScanlineOverlay() {
  noStroke();
  fill(0, 255, 80, 13);
  rect(0, scanLine, width, 2);

  float flicker = noise(noiseOff) * 255;
  stroke(0, flicker*0.2, 0, 50);
  strokeWeight(1.5);
  noFill();
  rect(1, 1, width-2, height-2, 2);

  // Vignette
  for (int i = 0; i < 20; i++) {
    fill(0, map(i, 0, 20, 45, 0));
    noStroke();
    rect(0, 0, i*3, height);
    rect(width-i*3, 0, i*3, height);
  }
}

// ================================================================
// RECORDING INDICATOR
// ================================================================
void drawRecordingIndicator() {
  if (!recording && !playback) return;
  textAlign(RIGHT);
  textSize(11);
  if (recording) {
    float blink = (frameCount % 40 < 20) ? 255 : 120;
    fill(255, 0, 0, blink);
    text("● REC  "+recBuffer.size()+" frames", width-10, height-26);
  } else {
    fill(0, 200, 255, 200);
    text("▶ PLAY  "+playPtr+"/"+recBuffer.size(), width-10, height-26);
  }
}

// ================================================================
// BELL SOUND
// ================================================================
void triggerBell() {
  if (bellCooldown > 0) return;
  bellCooldown = BELL_CD_MAX;
  bellOsc.freq(1200);
  bellEnv.play(bellOsc, 0.01, 0.08, 0.6, 0.35);
}

// ================================================================
// RECORDING & PLAYBACK
// ================================================================
void startRecording() { recBuffer.clear(); recording=true; playback=false; }

void stopRecording() {
  recording = false;
  try {
    recFile = createWriter("radar_rec.csv");
    for (String s : recBuffer) recFile.println(s);
    recFile.flush(); recFile.close();
    println("Saved "+recBuffer.size()+" frames.");
  } catch(Exception e) { println("Save error: "+e.getMessage()); }
}

void startPlayback() {
  if (recBuffer.size() == 0) {
    String[] lines = loadStrings("radar_rec.csv");
    if (lines != null) { recBuffer.clear(); for (String l:lines) recBuffer.add(l); }
  }
  if (recBuffer.size() > 0) {
    playback=true; recording=false; playPtr=0; playDelay=0;
  }
}

void stopPlayback() { playback = false; }

void feedPlayback() {
  if (playPtr >= recBuffer.size()) { stopPlayback(); return; }
  playDelay++;
  if (playDelay >= PLAY_SPEED) {
    playDelay = 0;
    String[] v = split(recBuffer.get(playPtr++), ',');
    if (v.length==2) try { rawAngle=float(v[0]); rawDist=float(v[1]); } catch(Exception e){}
  }
}

// ================================================================
// KEY CONTROLS
// ================================================================
void keyPressed() {
  if      (key=='r'||key=='R') { if (!recording) startRecording(); else stopRecording(); }
  else if (key=='p'||key=='P') { if (!playback)  startPlayback();  else stopPlayback(); }
  else if (key=='c'||key=='C') {
    dotCount=0; totalDetections=0; closestEver=9999;
  }
  else if (key=='+') PLAY_SPEED = max(1,  PLAY_SPEED-1);
  else if (key=='-') PLAY_SPEED = min(10, PLAY_SPEED+1);
}

// ================================================================
// SERIAL INPUT
// ================================================================
void serialEvent(Serial p) {
  String raw = p.readStringUntil('\n');
  if (raw == null) return;
  raw = trim(raw);
  String[] v = split(raw, ',');
  if (v.length != 2) return;
  try {
    float newAngle = float(trim(v[0]));
    float newDist  = float(trim(v[1]));
    // Count full sweeps
    if ((sweepDir>0 && newAngle < rawAngle-10) ||
        (sweepDir<0 && newAngle > rawAngle+10)) sweepCount++;
    rawAngle = newAngle;
    rawDist  = newDist;
  } catch(Exception e) {
    println("Bad data: " + raw);
  }
}

// ================================================================
// UTILS
// ================================================================
float lerpAngle(float a, float b, float t) {
  float d = b - a;
  while (d >  180) d -= 360;
  while (d < -180) d += 360;
  return a + d * t;
}