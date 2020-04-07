/*
  Roberto Venditti 06-June-2016 - original version
  Roberto Venditti 26-March-2017 - add functionality to lockout the primary mains (where mitre saw is connected).
  
*/

// operating constants
const double SAMPLING_TIME_SECONDS = 0.1;        // number of consecutive samples to take when calculating current
const double INIT_WINDOW_SECONDS = 0.5;          // once current is detected, time to wait before triggering SSR
const double END_WINDOW_SECONDS = 4;             // once current is ended, time to wait before stopping SSR
const double AMP_THRESHOLD_ACTIVATE_SSR = 0.4;   // Amps at which to trigger SSR
const double AMP_THRESHOLD_STOP_SSR = 0.3;       // Amps at which to trigger SSR
const long RUNTIME_UNTIL_TIMEOUT_MINUTES = 90;   // power saw mains will turn off after this time, even if power key is turned "ON"

// physical constants
const double MINUTES_PER_HOUR = 60;
const double SECONDS_PER_MINUTE = 60;
const double MILLIS_PER_SECOND = 1000;

// Arduino setup constants
const int PIN_SSR = 12;         // DIGITAL
const int PIN_ANALOG = A0;      // ANALOG  
const int PIN_MANUAL = 4;       // DIGITAL
const int PIN_LOCK_SWITCH = 7;
const int PIN_POWERSAW = 8;

const int PIN_LOCK_SWITCH_GROUND = 6;
const int PIN_POWERSAW_GROUND = 9;
const int PIN_POWERSAW_VCC = 10;

// output (controls SSR)
const int SSR_ON = HIGH;
const int SSR_OFF = LOW;

// output (controls SSR for power saw)
// replaced previous (unreliable) magnetic relay which was active low
const int SAW_RELAY_ON = HIGH;
const int SAW_RELAY_OFF = LOW;

// output from ACS712 current sensor
const int CURRENT_ON = HIGH;
const int CURRENT_OFF = LOW;

// true enables debug print statements
const boolean DEBUG_MODE = false;

// enable test cases
const String TEST_CASE = "";
//const String TEST_CASE = "test:saw_always_on";
//const String TEST_CASE = "test:10s_to_lockout";


class SwitchMonitor
{
  unsigned long previous_millis;
  unsigned long last_state_change_request_millis;
  long active_delay_interval_millis;
  int set_output_state_after_delay;
  long timeout_turn_output_on;
  long timeout_turn_output_off;
  long minutes_allowed_before_lockout; // secondary control on powersaw mains; even if key is set "on", will time out after this time and need to be reset (key off-on cycle)
  int logic_input_state_on;
  int logic_input_state_off;
  int logic_output_state_on;
  int logic_output_state_off;
  
  public:
  int desired_state_of_output;
  int last_input_switch_state;
  long seconds_remaining_to_lockout;
  long timeout_millis;

  // Constructor 
  public:
  void assign_variables(int init_val, long on=0, long off=0, int logic_input_on=HIGH, int logic_input_off=LOW, int logic_output_on=HIGH, int logic_output_off=LOW, long lockout_minutes=-1);
  
  private:
  void Check_For_State_Change( unsigned long current_millis, int active_state_input_switch )
  {
    if(DEBUG_MODE && minutes_allowed_before_lockout > 0){
      Serial.print("last_input_switch_state | active_state_input_switch: ");
      Serial.print(last_input_switch_state);
      Serial.print(" | ");
      Serial.println(active_state_input_switch);
    }
    if(last_input_switch_state != active_state_input_switch){
      last_state_change_request_millis = current_millis;
      if (last_input_switch_state == logic_input_state_off && active_state_input_switch == logic_input_state_on){
        set_output_state_after_delay = logic_output_state_on;
        active_delay_interval_millis = timeout_turn_output_on;
        timeout_millis = minutes_allowed_before_lockout*SECONDS_PER_MINUTE*MILLIS_PER_SECOND;
        seconds_remaining_to_lockout = timeout_millis/MILLIS_PER_SECOND;
        if (DEBUG_MODE){
          if(minutes_allowed_before_lockout > 0){
            Serial.print("resetting seconds_remaining_to_lockout: ");
            Serial.println(seconds_remaining_to_lockout);
          }
        }
            
//*****DEBUG OVERRIDE*****
      if (TEST_CASE=="test:10s_to_lockout"){
        minutes_allowed_before_lockout = 1;
        seconds_remaining_to_lockout = 10;
        if (DEBUG_MODE){
          Serial.print("TEST CASE: seconds_remaining_to_lockout set to: ");
          Serial.print(seconds_remaining_to_lockout);
          Serial.println(" | applied debug override to: 10");
        }
      }

      }else if(last_input_switch_state == logic_input_state_on && active_state_input_switch == logic_input_state_off){
        set_output_state_after_delay = logic_output_state_off;
        active_delay_interval_millis = timeout_turn_output_off;
        timeout_millis = 0;
        seconds_remaining_to_lockout = 0;
        if (DEBUG_MODE){
          if(minutes_allowed_before_lockout > 0){
            Serial.print("zero out seconds_remaining_to_lockout: ");
            Serial.println(seconds_remaining_to_lockout);
          }
        }
      }else{
        if (DEBUG_MODE){
          Serial.println('WTF! Is this even possible?');
        }  
      }
    }
  }

  public:
  void Update(unsigned long current_millis, int active_switch_state)
  {
    Check_For_State_Change( current_millis, active_switch_state );    
    last_input_switch_state = active_switch_state;
    if (current_millis - last_state_change_request_millis >= active_delay_interval_millis) {
      if (desired_state_of_output != set_output_state_after_delay){
        desired_state_of_output = set_output_state_after_delay;
      }
    }
    timeout_millis -= (current_millis - previous_millis);
    timeout_millis = max(0, timeout_millis);  // floor to zero; avoid overflow problems, etc
    seconds_remaining_to_lockout = timeout_millis/MILLIS_PER_SECOND;
    
    if (DEBUG_MODE){
      if(minutes_allowed_before_lockout > 0){
        Serial.print("lockout timer status: ");
        Serial.print(current_millis);
        Serial.print(" | ");
        Serial.print(previous_millis);
        Serial.print(" | ");
        Serial.print(timeout_millis);
        Serial.print(" | ");
        Serial.println(seconds_remaining_to_lockout);
      }
    }
    
    if (timeout_millis <= 0 && minutes_allowed_before_lockout >= 0){
      // lockout - turn it off now, regardless of other conditions
      // switch has to go from OFF to ON to reset timer (i.e. switch cycle)
      if (DEBUG_MODE){
        Serial.println("triggering lockout");
      }
      desired_state_of_output = logic_output_state_off;
    } 
    previous_millis = current_millis;
  }  
};

void SwitchMonitor::assign_variables(int init_val, long on, long off, int logic_input_on, int logic_input_off, int logic_output_on, int logic_output_off, long lockout_minutes)
{
// http://stackoverflow.com/questions/18806141/move-object-creation-to-setup-function-of-arduino
    last_input_switch_state = init_val;
    timeout_turn_output_on = on;
    timeout_turn_output_off = off;
    minutes_allowed_before_lockout = lockout_minutes;

    logic_input_state_on = logic_input_on;
    logic_input_state_off = logic_input_off;
    logic_output_state_on = logic_output_on;
    logic_output_state_off = logic_output_off;
    set_output_state_after_delay = logic_input_state_off;
    desired_state_of_output = logic_input_state_off;
    previous_millis = 0;
    last_state_change_request_millis = 0;
    active_delay_interval_millis = 0;
    seconds_remaining_to_lockout = 0;
    timeout_millis = 0;
    return;
}

// input monitors
SwitchMonitor switch_manual;
SwitchMonitor switch_current_sensor;
SwitchMonitor switch_lockout_mains;


double convert_sensor_rms_voltage_to_amps(double rms_voltage)
{
  // ACS712 chip --> 0V = 0A; 15A/V or 66mV/A
  double ACS712_AMPS_PER_VOLT = 15;
  double amps_in_wire = rms_voltage*ACS712_AMPS_PER_VOLT;
  return amps_in_wire;
}


double take_an_amp_reading(int pin_id)
{
  // http://henrysbench.capnfatz.com/henrys-bench/arduino-current-measurements/acs712-arduino-ac-current-tutorial/
  double analog_voltage = 0;
  double rms_voltage = 0;
  double max_voltage_reading = -99;
  double min_voltage_reading =  99;
  double amp_reading = 0;
  
  unsigned long start_time = millis();
  
  while( (millis()-start_time) < (SAMPLING_TIME_SECONDS*MILLIS_PER_SECOND) ){
    analog_voltage = analogRead(pin_id) * (5.0 / 1023.0);
    if (analog_voltage > max_voltage_reading) {
      max_voltage_reading = analog_voltage;
    }else if (analog_voltage < min_voltage_reading) {
      min_voltage_reading = analog_voltage;
    }
  }
  rms_voltage = ((max_voltage_reading - min_voltage_reading)/2.0) *0.7071;
  amp_reading = convert_sensor_rms_voltage_to_amps(rms_voltage);

  if (DEBUG_MODE){
    Serial.print("ACS712 current sensor readings: ");
    Serial.print(max_voltage_reading);
    Serial.print(" | ");
    Serial.print(min_voltage_reading);
    Serial.print(" | ");
    Serial.print(rms_voltage);
    Serial.print(" | ");
    Serial.println(amp_reading);
  }

  return amp_reading;
}


int get_digital_read_from_current_sensor(int pin_id)
{
  int digital_output = -1; //previous_digital_read;
  double sensor_amps = take_an_amp_reading(pin_id);
  if(sensor_amps >= AMP_THRESHOLD_ACTIVATE_SSR){
    digital_output = HIGH;
  }else if(sensor_amps <= AMP_THRESHOLD_STOP_SSR){
    digital_output = LOW;
  }
  
//*****DEBUG OVERRIDE*****
  if (TEST_CASE=="test:saw_always_on"){
    digital_output = HIGH;
  }
  
  return digital_output;
}


void setup()
{
  if (DEBUG_MODE){
    Serial.begin(9600);
    Serial.println("starting program");
  }
  
  // power pins
  pinMode(PIN_LOCK_SWITCH_GROUND, OUTPUT);
  digitalWrite(PIN_LOCK_SWITCH_GROUND, LOW); 
  pinMode(PIN_POWERSAW_GROUND, OUTPUT);
  digitalWrite(PIN_POWERSAW_GROUND, LOW); 
  pinMode(PIN_POWERSAW_VCC, OUTPUT);
  digitalWrite(PIN_POWERSAW_VCC, HIGH);
  
  // initialize the pin to control the SSR (starts OFF)
  pinMode(PIN_SSR, OUTPUT);
  digitalWrite(PIN_SSR, SSR_OFF); 
  
  // initialize the pin to control manual activation of vacuum
  // activate internal pullup (https://www.arduino.cc/en/Tutorial/DigitalPins)
  pinMode(PIN_MANUAL, INPUT);
  digitalWrite(PIN_MANUAL, HIGH); // enable internal pullup - avoid need for external resistor; but means switch actuation needs to ground pin

  pinMode(PIN_POWERSAW, OUTPUT);
  digitalWrite(PIN_POWERSAW, SAW_RELAY_OFF);
  
  pinMode(PIN_LOCK_SWITCH, INPUT);
  digitalWrite(PIN_LOCK_SWITCH, HIGH); // enable internal pullup - avoid need for external resistor; but means switch actuation needs to ground pin
  
  // setup switch monitors (must be done after class declaration)
  switch_manual.assign_variables( digitalRead(PIN_MANUAL) );
  switch_current_sensor.assign_variables( get_digital_read_from_current_sensor(PIN_ANALOG), INIT_WINDOW_SECONDS*MILLIS_PER_SECOND, END_WINDOW_SECONDS*MILLIS_PER_SECOND );
  //switch_lockout_mains.assign_variables( digitalRead(PIN_LOCK_SWITCH), 0, 0, LOW, HIGH, HIGH, LOW, RUNTIME_UNTIL_TIMEOUT_MINUTES );
  switch_lockout_mains.assign_variables( digitalRead(PIN_LOCK_SWITCH), 0, 0, LOW, HIGH, SAW_RELAY_ON, SAW_RELAY_OFF, RUNTIME_UNTIL_TIMEOUT_MINUTES );
}


void loop ()
{
  unsigned long currentMillis = millis();
  
  switch_lockout_mains.Update( currentMillis, digitalRead(PIN_LOCK_SWITCH) );
  if (switch_lockout_mains.desired_state_of_output == SAW_RELAY_ON){
    digitalWrite(PIN_POWERSAW, SAW_RELAY_ON);
  }else{
    if(get_digital_read_from_current_sensor(PIN_ANALOG) != CURRENT_ON){
      // don't kill the power if saw is running (might ruin a workpiece if lockout timer triggers when saw is mid-cut)
      // this means we cannot use this circuit for any kind of emergyency shutoff!
      digitalWrite(PIN_POWERSAW, SAW_RELAY_OFF);    
    }else{
      if (DEBUG_MODE){
        Serial.println("take no timeout action because saw is reported as running");
      }
    }
  }

  switch_manual.Update( currentMillis, digitalRead(PIN_MANUAL) );  
  switch_current_sensor.Update( currentMillis, get_digital_read_from_current_sensor(PIN_ANALOG) );
  
//*****DEBUG OVERRIDE*****
  if (TEST_CASE=="test:saw_always_on"){
    switch_current_sensor.desired_state_of_output = SSR_ON;
  }
  
  if (switch_manual.desired_state_of_output == SSR_ON || switch_current_sensor.desired_state_of_output == SSR_ON){
    digitalWrite(PIN_SSR, SSR_ON);
  }else{
    digitalWrite(PIN_SSR, SSR_OFF);
  }

  if (DEBUG_MODE){
    delay(1000);
  }
}
