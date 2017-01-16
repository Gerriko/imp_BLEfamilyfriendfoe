const FRIENDSTARTHOURS = 9;         //9am
const FRIENDENDHOURS = 21;         //9pm

BLE <- {
    mac = "",                        // BLE device Mac Address
    nme = "",                        // BLE name
    FamUsrs = "--ENTER_SHORT_FAMILY_CODE_HERE--",                    // Username for family to use for BLE device
    FrdUsrs = "--ENTER_SHORT_FRIEND_CODE_HERE--"                    // Username for friends to use for BLE device
};

function httpHandler(request,response) {
    try 
    {
        local method = request.method.toupper();
        response.header("Access-Control-Allow-Origin", "*");

        if (method == "POST") {
            if (BLE.mac.len) {
                local devArray = split(request.body,",");
                if (devArray.len()) {
                    local mcStr = "";
                    local BLEmacValid = false;
                    local BLEnmeValid = false;
                    local usrNme = "";
                    local usrNmeFamValid = false;
                    local usrNmeFrdValid = false;
                    foreach (i, ble in devArray) {
                        if (i) {
                            if (ble == "L_R") {
                                response.send(200, "0GOODBYE");
                                device.send("USRinfo", {"uFAM":usrNmeFamValid, "uFRD":usrNmeFrdValid});
                                return;
                            }
                            else {
                                local BLEdevs = split(ble," ");
                                if (BLEdevs.len() == 3) {
                                    local mc = split(BLEdevs[0],":");
                                    if (mc.len() == 6) {
                                        mcStr = mc[0]+mc[1]+mc[2]+mc[3]+mc[4]+mc[5];
                                        //server.log("BLE Dev"+i+ "= MAC: "+mcStr+" Name: "+BLEdevs[1]+" Signal: "+BLEdevs[2]);
                                        //Check against API data
                                        if (BLE.mac == mcStr) BLEmacValid = true;
                                        if (BLE.nme == BLEdevs[1]) BLEnmeValid = true;
                                    }
                                }
                            }
                        } 
                        else {
                            usrNme = strip(ble.toupper());
                            //server.log("BLE userName: " + usrNme);
                            if (BLE.FamUsrs == usrNme.toupper()) usrNmeFamValid = true; 
                            else {
                                if (BLE.FrdUsrs == usrNme.toupper()) usrNmeFrdValid = true;
                            }
                        }
                    }
                    if (BLEmacValid && BLEnmeValid && (usrNmeFamValid || usrNmeFrdValid)) {
                        if (usrNmeFamValid) response.send(200, "1Validated as Family.");
                        else {
                            //Check time of day - friends only allows between 9am to 9pm
                            local now = date();
                            if ((now.hour+1) >= FRIENDSTARTHOURS && (now.hour+1) <= FRIENDENDHOURS) response.send(200, "1Validated as Friend.");
                            else {
                                response.send(200, "3Sorry my Friend. Outside of hours.");
                                usrNmeFrdValid =false;  // reset as out of hours
                            }
                        }
                        //Send cmd to device to say "family or friend present"
                        device.send("USRinfo", {"uFAM":usrNmeFamValid, "uFRD":usrNmeFrdValid});
                    }
                    else {
                        if (!BLEmacValid || !BLEnmeValid) response.send(200, "2BLE Device Not Found, scanning again.");
                        else {
                            if (!usrNmeFamValid && !usrNmeFrdValid) response.send(200, "3Sorry, wrong User Name. Try again.");
                        }
                    }
                }
                else response.send(200, "4Bad Data");
            }
            else response.send(200, "4BLE Device not Enabled");
        }
    }
    catch(error)
    {
        response.send(500, "Internal Server Error: " + error)
    }
}

// Basic wrapper to send a Slack notification
function HttpSlackPostWrapper (data) {
    
    //Slack integration
    local SlackURL = "https://hooks.slack.com/services/########/#######/#################"; // **** ENTER YOUR CORRECT URL HERE -------
    local message = "";
    server.log("Slack No: " + data.T);
    switch (data.T) {
        case 1:
            message = "Someone just walked into room";
            break;
        case 2:
            message = "PIR alarm has just triggered";
            break;
        case 3:
            message = "PIR alarm triggered again";
            break;
        case 4:
            message = "Family member disarmed PIR";
            break;
        case 5:
            message = "A friend disarmed PIR";
            break;
        case 6:
            message = "PIR is now re-armed";
            break;
        case 7:
            message = "PIR device has restarted";
            break;
    }
    local request = http.post( SlackURL,                    //URL
                    {"Content-Type": "application/json"},   //header
                    http.jsonencode({"text": message}) );   //message string
    
    local response = request.sendsync();
    server.log("Slack HTTPResponse: " + response.statuscode + " - " + response.body);
}


function DeviceLogIn_handler(devdata) {
    // Placeholder to record how device restarted etc.... snippet not included
    
    //HttpSlackPostWrapper ({"T":7});   // uncomment if you want a notification that device rebooted
}

function BLEdev_handler(devdata) {
    server.log("BLE Device registered: MAC("+devdata.bMAC+") + NAME("+devdata.bNME+")");
    //Update API
    BLE.mac = devdata.bMAC;
    BLE.nme = devdata.bNME;
}

/* REGISTER HTTP HANDLER -----------------------------------------------------*/
http.onrequest(httpHandler);

device.on("PingHQ", DeviceLogIn_handler); 
device.on("BLEinfo", BLEdev_handler); 
device.on("SLCKnotify", HttpSlackPostWrapper);
