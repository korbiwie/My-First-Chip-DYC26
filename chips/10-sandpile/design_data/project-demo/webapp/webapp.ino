#include <WiFi.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <SPI.h>

// -----------------------------
// Wi-Fi Credentials (AP Mode)
// -----------------------------
const char* ssid = "sandpile";
const char* password = "sandonsand";

WebServer server(80);

// -----------------------------
// SPI CONFIG
// -----------------------------
#define PIN_MOSI 23
#define PIN_MISO 19
#define PIN_SCK  18
#define PIN_CS   5

SPIClass spi(VSPI);
SPISettings spiSettings(1000000, MSBFIRST, SPI_MODE0);

// -----------------------------
// Registers
// -----------------------------
#define REG_CHIP_ID     0x0A
#define REG_CONTROL     0x01
#define REG_GRID_SIZE   0x0C
#define REG_DROP_MODE   0x0D
#define REG_SPEED       0x0E
#define REG_RANDOM_SEED 0x0F
// -----------------------------
// Globals
// -----------------------------
uint16_t gridSize = 1;
bool dropMode = 0;
uint16_t speedVal = 0;
bool appRunning = false;
unsigned long lastUpdateTime = 0;

// -----------------------------
// Binary Helpers
// -----------------------------
String bin(uint16_t v, uint8_t size)
{
  char b[size + 1]; b[size]='\0';
  for(int i=0;i<size;i++) b[size - 1 -i]=((v>>i)&1)+'0';
  return String(b);
}

// -----------------------------
// BEAUTIFIED HTML UI
// -----------------------------
String htmlPage()
{
  return R"rawliteral(
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link href="https://fonts.googleapis.com/css2?family=Orbitron:wght@400;700&display=swap" rel="stylesheet">
<style>
html {  
  height: 100%;
}
body {
  margin:0;
  height: 100%;
  font-family:'Orbitron',sans-serif;
  background:linear-gradient(135deg,#0f2027,#203a43,#2c5364);
  color:white;
  text-align:center;
  display:flex;
  align-items:center;
  justify-content:center;
}
.panel {
  background:rgba(0,0,0,0.45);
  backdrop-filter:blur(10px);
  width:360px;
  padding:25px;
  border-radius:20px;
  box-shadow:0 0 25px rgba(0,0,0,0.6);
}
h2 { margin-top:0; }
label { display:block; margin-top:15px; }
input[type=range] { width:100%; }
.valueBox {
  font-size:18px;
  margin-top:5px;
  color:#00ffd5;
}
button {
  margin:10px;
  padding:12px 22px;
  border:none;
  border-radius:12px;
  font-size:15px;
  cursor:pointer;
  background:linear-gradient(45deg,#00ffd5,#008cff);
  color:black;
  font-weight:bold;
}
button:hover:not(:disabled) { transform:scale(1.05); }
button:disabled {
  opacity:0.5;
  cursor:not-allowed;
  background:#666;
}
.chipid { font-size:20px; color:#00ffd5; }
</style>
</head>
<body>

<div class="panel">
<h2>Sandpile Controller</h2>

<label>Chip ID</label>
<div class="chipid" id="chipid">Reading...</div>

<label>Grid Size</label>
<select id="grid" style="width:100%; padding:8px; border-radius:8px; font-size:15px;">
<option value="4">4x4</option>
<option value="8" selected>8x8</option>
<option value="12">12x12</option>
<option value="16">16x16</option>
<option value="32">32x32</option>
</select>

<label>Speed</label>
<input type="range" min="1" max="127" value="50" id="speed">
<div class="valueBox" id="speedval">50</div>

<label>Drop Mode</label>
<input type="radio" name="mode" value="1" checked> Central
<input type="radio" name="mode" value="0"> Random

<br><br>
<button id="startBtn" onclick="startApp()">START</button>
<button id="stopBtn" onclick="stopApp()" disabled>STOP</button>
<button onclick="resetApp()">RESET</button>
</div>

<script>
const speedSlider=document.getElementById("speed");
speedSlider.oninput=()=>{
 document.getElementById("speedval").innerHTML=speedSlider.value;
};

let updateInterval=null;

function startApp(){
 if(document.getElementById("startBtn").disabled) return;
 
 let grid=document.getElementById("grid").value;
 let speed=document.getElementById("speed").value;
 let mode=document.querySelector('input[name="mode"]:checked').value;
 
 document.getElementById("startBtn").disabled=true;
 document.getElementById("stopBtn").disabled=false;
 
 fetch(`/start?grid=${grid}&speed=${speed}&mode=${mode}`);
 
 updateInterval=setInterval(()=>{
  fetch('/update');
 },100);
}

function stopApp(){
 if(document.getElementById("stopBtn").disabled) return;
 
 if(updateInterval){
  clearInterval(updateInterval);
  updateInterval=null;
 }
 fetch('/stop');
 document.getElementById("startBtn").disabled=false;
 document.getElementById("stopBtn").disabled=true;
}

function resetApp(){ 
 if(updateInterval){
  clearInterval(updateInterval);
  updateInterval=null;
 }
 fetch('/reset');
 document.getElementById("startBtn").disabled=false;
 document.getElementById("stopBtn").disabled=true;
}

fetch('/chipid').then(r=>r.text()).then(t=>{
 document.getElementById("chipid").innerHTML=t;
});
</script>

</body>
</html>
)rawliteral";
}

// -----------------------------
// SPI Helpers
// -----------------------------
void build_bytes(uint8_t addr, uint16_t data, uint8_t *bytes)
{
  bytes[0] = (addr & 0xF) << 4;
  bytes[0] |= (data >> 8);
  bytes[1] = data & 0xFF;
}

uint16_t spiTransfer16(uint8_t *tx_data)
{
  uint8_t rx_data[2];

  spi.beginTransaction(spiSettings);
  digitalWrite(PIN_CS, LOW);

  spi.transferBytes(tx_data, rx_data, 2);

  digitalWrite(PIN_CS, HIGH);
  spi.endTransaction();

  return rx_data[1];
}

// -----------------------------
// Register Router
// -----------------------------
uint16_t routeRegister(uint8_t addr, uint16_t data, bool writeMode)
{
  uint8_t tx[2];
  build_bytes(addr, data, tx);

  Serial.printf(
    "SPI TX -> Addr:0x%X (0b%s) Data:0x%03X (0b%s)\n",
    addr,
    bin(addr, 4).c_str(),
    data,
    bin(data, 12).c_str()
  );

  uint16_t rx = spiTransfer16(tx);

  uint8_t respAddr = (rx >> 12) & 0xF;
  uint16_t respData = rx & 0x0FFF;

  Serial.printf(
    "SPI RX <- Addr:0x%X (0b%s) Data:0x%03X (0b%s)\n",
    respAddr,
    bin(respAddr, 4).c_str(),
    respData,
    bin(respData, 12).c_str()
  );

  switch(addr)
  {
    case 0x00: break;
    case 0x01: break;
    case 0x02: gridSize = data; break;
    case 0x03: dropMode = data & 0x1; break;
    case 0x04: speedVal = data; break;
    case 0x05: break;
    case 0x06: break;
    case 0x07: break;
    case 0x08: break;
    case 0x09: break;
    case 0x0A: break;
    case 0x0B: break;
    case 0x0C: break;
    case 0x0D: break;
    case 0x0E: break;
    case 0x0F: break;
  }

  return respData;
}

// -----------------------------
// Random Seed (10‑bit)
// -----------------------------
uint16_t generateSeed()
{
  uint16_t seed = 0;

  for(int i=0;i<10;i++)
  {
    uint8_t rand;
    // replaced to take random number generator from esp, temperature has issues to run together with wifi
    esp_fill_random(&rand, 1);
    uint8_t lsb = rand & 0x1;
    seed |= (lsb << i);
  }

  Serial.printf(
    "Generated Seed: 0x%03X (0b%s)\n",
    seed,
    bin(seed, 10).c_str()
  );

  return seed;
}

// -----------------------------
// Handlers
// -----------------------------
void handleRoot(){ server.send(200,"text/html",htmlPage()); }

void handleChipID()
{
  uint16_t id = routeRegister(REG_CHIP_ID,0,false);

  String hexStr = "0x" + String(id, HEX);
  hexStr.toUpperCase();

  server.send(200,"text/plain",hexStr);
}

void handleStart()
{
  uint16_t grid = server.arg("grid").toInt();
  uint16_t speed = server.arg("speed").toInt();
  uint8_t mode = server.arg("mode").toInt();

  routeRegister(REG_GRID_SIZE,grid,true);
  routeRegister(REG_SPEED,speed,true);
  routeRegister(REG_DROP_MODE,mode,true);

  uint16_t seed = generateSeed();
  routeRegister(REG_RANDOM_SEED,seed,true);

  uint16_t start_command = 0x1;
  routeRegister(REG_CONTROL, start_command, true);

  appRunning = true;
  lastUpdateTime = millis();
  server.send(200,"text/plain","STARTED");
}

void handleUpdate()
{
  if(!appRunning) {
    server.send(200,"text/plain","NOT_RUNNING");
    return;
  }

  uint16_t seed = generateSeed();
  routeRegister(REG_RANDOM_SEED,seed,true);

  server.send(200,"text/plain","UPDATED");
}

void handleStop()
{
  uint16_t stop_command = 0x0;
  routeRegister(REG_CONTROL, stop_command, true);
  appRunning = false;
  server.send(200,"text/plain","STOPPED");
}

void handleReset()
{
  uint16_t reset_command = 0x3;
  routeRegister(REG_CONTROL, reset_command,true);
  appRunning = false;
  server.send(200,"text/plain","RESET");
}

// -----------------------------
// Setup
// -----------------------------
void setup()
{
  Serial.begin(115200);

  pinMode(PIN_CS, OUTPUT);
  digitalWrite(PIN_CS, HIGH);

  spi.begin(PIN_SCK, PIN_MISO, PIN_MOSI, PIN_CS);

  WiFi.softAP(ssid,password);
  Serial.println("AP Started");

  if(MDNS.begin("sandpile"))
    Serial.println("mDNS started -> sandpile.local");

  server.on("/",handleRoot);
  server.on("/chipid",handleChipID);
  server.on("/start",handleStart);
  server.on("/update",handleUpdate);
  server.on("/stop",handleStop);
  server.on("/reset",handleReset);

  server.begin();
}

// -----------------------------
// Loop
// -----------------------------
void loop(){ server.handleClient(); }
