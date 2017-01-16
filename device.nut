/* This code copyright protected (c) 2017 Gerriko IoT ------------------------*/
/* Developed by Colin Gerrish (Gerriko IoT) ----------------------------------*/
/* This file is licensed under the MIT License -------------------------------*/
/* http://opensource.org/licenses/MIT ----------------------------------------*/

// UART bus, Trigger and GPIO pins
UART <- hardware.uart1289;
PIR <- hardware.pin2;
Buzzer <- hardware.pin7;

const PIRWARNPERIOD = 20;       // time in seconds before warning buzzer changes to alarm buzzer
const PIRRESETMODEPERIOD = 240; // if after 4 minutes no more alarms triggered then reset mode back to warning status

local PIRmode = 1;              // 1 = warning, 2 = alarm
local PIRtrig = false;
local PIRpulse = 0;             // pulse counter 
local PIRtimer = null;          // keep track of how long
local PIRalarmWakeUp = null;    // wakeup timer event

local BLEon = false;
local BLEmac = "";
local BLEname = "";

local USR = {
    Present = 0,    // 1 = family, 2 = friend
    Delay = 20.0,   // Delay in seconds before user presence changes
    Notify = true,
    Timer = null
};

function BLE_UARTcallbackfnc() {
    imp.sleep(0.1);
    local BLEstr = UART.readstring();
    BLEstr = strip(BLEstr);
    local BLEstrLen = BLEstr.len();
    if (BLEstrLen) {
        if (BLEstrLen < 6) {
            if (BLEstr == "OK") {
                BLEon = true;
                UART.write("AT+ADDR?");
            }
        }
        else {
            local BLEindex = BLEstr.find("+ADDR");
            if (BLEindex != null) {
                BLEmac = BLEstr.slice(BLEindex+6);
                if (BLEmac.len()) {
                    imp.sleep(0.1);
                    UART.write("AT+NAME?");
                }
            }
            BLEindex = BLEstr.find("+NAME");
            if (BLEindex != null) {
                BLEname = BLEstr.slice(BLEindex+6,BLEstr.len()-1);
                agent.send("BLEinfo", {"bMAC":BLEmac, "bNME":BLEname});
            }
        }
    }
}

function PIR_GPIOreadCallbackfnc() {
    if (PIR.read()) {
        // Is there a family or friend present - if not then...
        if (!USR.Present) {
            if (PIRmode == 1) {
                if (!PIRpulse) {
                    agent.send("SLCKnotify", {"T":1});        // 1 = first PIR notification (at warning level)
                    server.log("PIR 1st trigger");
                    PIRtimer = hardware.millis()/1000;
                    //Set up timer to reset alarm after some time period
                    PIRalarmWakeUp = imp.wakeup(PIRRESETMODEPERIOD, changeAlarmingStatus);
                }
                PIRpulse++;
                server.log("PIR warn no: "+ PIRpulse +" timer " + (hardware.millis()/1000 - PIRtimer));
                if ((hardware.millis()/1000 - PIRtimer) > PIRWARNPERIOD) {
                    if (PIRpulse > 2) {
                        PIRmode = 2;
                        server.log("PIR mode change to " + PIRmode);
                        agent.send("SLCKnotify", {"T":2});        // 2 = first PIR alarm notification
                    }
                    PIRpulse = 0;
                    PIRtimer = hardware.millis()/1000;
                    //Set up timer to reset alarm after some time period
                    if (PIRalarmWakeUp) imp.cancelwakeup(PIRalarmWakeUp);
                }
                else server.log("PIR warn trigger");

                for (local i = 0; i < 3; i++) {
                    Buzzer.write(1);
                    imp.sleep(0.1);
                    Buzzer.write(0);
                    imp.sleep(0.2);
                }
            }
            else if (PIRmode >= 2) {
                Buzzer.write(1);
                PIRtrig = true;
                PIRpulse++;
                if (PIRpulse >= 10) {
                    server.log("PIR alarm notification");
                    agent.send("SLCKnotify", {"T":3});        // 3 = PIR alarm again notification
                    PIRpulse = 0;
                }
            }
        }
    }
    else {
        if (PIRmode >= 2 && PIRtrig) {
            server.log("PIR alarm trigger " + PIRpulse);
            for (local i = 0; i < 4; i++) {
                Buzzer.write(1);
                imp.sleep(0.2);
                Buzzer.write(0);
                imp.sleep(0.1);
            }
            PIRtrig = false;
            PIRtimer = hardware.millis()/1000;
            //Set up timer to reset alarm after some time period
            if (PIRalarmWakeUp) imp.cancelwakeup(PIRalarmWakeUp);
            else PIRalarmWakeUp = imp.wakeup(PIRRESETMODEPERIOD, changeAlarmingStatus);
        }
        if (USR.Present && PIRmode >= 2) PIRmode = 1;
    }
}

function USRinfo_handler(data) {
    if (data.uFAM) {
        USR.Present = 1;
        if (USR.Timer) imp.cancelwakeup(USR.Timer);
        USR.Timer = imp.wakeup(USR.Delay, changeUsrStatus);
        if (USR.Notify) {
            agent.send("SLCKnotify", {"T":4});        // 4 = Family member disarmed
            USR.Notify = false;
        }
    }
    else {
        if (data.uFRD) {
            USR.Present = 2;
            if (USR.Timer) imp.cancelwakeup(USR.Timer);
            USR.Timer = imp.wakeup(USR.Delay, changeUsrStatus);
            if (USR.Notify) {
                agent.send("SLCKnotify", {"T":5});        // 5 = Friend disarmed
                USR.Notify = false;
            }
        }
        else {
            USR.Present = 0;
            if (USR.Timer) imp.cancelwakeup(USR.Timer);
            agent.send("SLCKnotify", {"T":6});        // 6 = PIR re-armed
            USR.Notify = true;
        }        
    }
}

function changeUsrStatus() {
    USR.Present = 0;
}

function changeAlarmingStatus() {
    PIRmode = 1;
    PIRtrig = false;
    PIRtimer = 0;
    PIRpulse = 0;
    Buzzer.write(0);
}

function DeviceNowOn() {
    imp.wakeup(1, function() {
        agent.send("PingHQ", {"bST":hardware.millis(), "bWR": hardware.wakereason()});
        imp.sleep(0.1);
        server.log("PIR ini state: " + PIR.read());
        UART.write("AT");
        imp.wakeup(15, function() {
            if (!BLEon) UART.write("AT");
        });
        //Test Buzzer
        for (local i = 0; i < 6; i++) {
            Buzzer.write(1);
            imp.sleep(0.1);
            Buzzer.write(0);
            imp.sleep(0.1);
        }
    });
}

// Hardware Configuration
// ---------------------------------------------------------------------- 
UART.configure(9600, 8, PARITY_NONE, 1, NO_CTSRTS, BLE_UARTcallbackfnc);
PIR.configure(DIGITAL_IN, PIR_GPIOreadCallbackfnc);
Buzzer.configure(DIGITAL_OUT, 0);

agent.on("USRinfo", USRinfo_handler); 

DeviceNowOn();
