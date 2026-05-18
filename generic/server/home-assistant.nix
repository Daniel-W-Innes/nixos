_:

{
  services.home-assistant = {
    enable = true;
    extraComponents = [
      # Components required to complete the onboarding
      "analytics"
      "google_translate"
      "met"
      "radio_browser"
      "shopping_list"
      # Recommended for fast zlib compression
      # https://www.home-assistant.io/integrations/isal
      "isal"
    ];
    config = {
      http = {
        server_host = "127.0.0.1";
        server_port = 8123;
      };
      default_config = { };
      homeassistant = {
        auth_mfa_modules = [ { type = "totp"; } ];
      };
      tts = [ { platform = "google_translate"; } ];
      automation = [
        {
          id = "1701303174458";
          alias = "Flood";
          description = "";
          trigger = [
            {
              platform = "state";
              entity_id = [
                "binary_sensor.shellyflood_349454777b36_flood"
                "binary_sensor.shellyflood_349454772e5a_flood"
                "binary_sensor.shellyflood_34945478b6cc_flood"
              ];
              from = null;
              to = "on";
            }
          ];
          condition = [ ];
          action = [
            {
              service = "notify.mobile_app_pixel_8_pro";
              data = {
                title = "Flood Detected";
                message = "flood detected by {{trigger.entity_id}}";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1701303438706";
          alias = "Battery";
          description = "";
          trigger = [
            {
              platform = "numeric_state";
              entity_id = [
                "sensor.shellyflood_349454777b36_battery"
                "sensor.shellyflood_349454772e5a_battery"
                "sensor.shellyplusht_c049ef8af210_battery"
                "sensor.shellyht_746f2a_battery"
                "sensor.bedroom_battery"
                "sensor.shellyflood_34945478b6cc_battery"
                "sensor.shellyht_746b8a_battery"
                "sensor.shellyht_747622_battery"
              ];
              below = 30;
            }
          ];
          condition = [ ];
          action = [
            {
              service = "notify.mobile_app_pixel_8_pro";
              data = {
                title = "Low battery";
                message = "The battery for {{trigger.entity_id}} is running low.";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1702136119622";
          alias = "HVAC load 40";
          description = "";
          triggers = [
            {
              entity_id = [ "sensor.central_hvac_load" ];
              above = 60;
              trigger = "numeric_state";
              for = {
                hours = 1;
                minutes = 0;
                seconds = 0;
              };
            }
          ];
          conditions = [ ];
          actions = [
            {
              data = {
                title = "High Central HVAC load";
                message = "Central HVAC load higher than expected at {{trigger.to_state}}";
              };
              action = "notify.mobile_app_pixel_8_pro";
            }
          ];
          mode = "single";
        }
        {
          id = "1704053520308";
          alias = "Backdoor open";
          description = "";
          trigger = [
            {
              platform = "state";
              entity_id = [ "binary_sensor.alarm_panel_pro_ab24b8_backdoor" ];
              to = "on";
              from = "off";
            }
          ];
          condition = [ ];
          action = [
            {
              service = "notify.mobile_app_pixel_8_pro";
              data = {
                title = "Backdoor Open";
                message = "The backdoor is open";
                data = {
                  channel = "Alarms";
                };
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1704565768294";
          alias = "Frontdoor Open";
          description = "";
          trigger = [
            {
              platform = "state";
              entity_id = [ "binary_sensor.alarm_panel_pro_ab24b8_frontdoor" ];
              to = "on";
              from = "off";
            }
          ];
          condition = [ ];
          action = [
            {
              service = "notify.mobile_app_pixel_8_pro";
              data = {
                title = "Frontdoor Open";
                message = "The frontdoor is open";
                data = {
                  channel = "Alarms";
                };
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1704848065128";
          alias = "Door open too long";
          description = "";
          trigger = [
            {
              platform = "state";
              entity_id = [ "binary_sensor.door_sensors" ];
              to = "on";
              for = {
                hours = 0;
                minutes = 10;
                seconds = 0;
              };
            }
          ];
          condition = [ ];
          action = [
            {
              service = "notify.mobile_app_pixel_8_pro";
              metadata = { };
              data = {
                title = "Door open";
                message = "A door has been open for too long";
                data = {
                  channel = "Alarms";
                };
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1706149906723";
          alias = "Mornings at home";
          description = "";
          trigger = [
            {
              platform = "time";
              at = "07:00:00";
            }
          ];
          condition = [
            {
              condition = "state";
              entity_id = "person.daniel_innes";
              state = "home";
            }
            {
              condition = "state";
              entity_id = "person.emma_l";
              state = "not_home";
            }
          ];
          action = [
            {
              service = "climate.set_temperature";
              metadata = { };
              data = {
                temperature = 20.5;
              };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1706150014020";
          alias = "Nights at home";
          description = "";
          trigger = [
            {
              platform = "time";
              at = "21:00:00";
            }
          ];
          condition = [
            {
              condition = "state";
              entity_id = "person.daniel_innes";
              state = "home";
            }
            {
              condition = "state";
              entity_id = "person.emma_l";
              state = "not_home";
            }
          ];
          action = [
            {
              service = "climate.set_temperature";
              metadata = { };
              data = {
                temperature = 18;
              };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1706150120996";
          alias = "Vacation";
          description = "";
          trigger = [
            {
              platform = "state";
              entity_id = [ "person.daniel_innes" ];
              to = "not_home";
              for = {
                hours = 8;
                minutes = 0;
                seconds = 0;
              };
            }
          ];
          condition = [ ];
          action = [
            {
              service = "climate.set_temperature";
              metadata = { };
              data = {
                temperature = 17;
                hvac_mode = "heat";
              };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1706150408841";
          alias = "Home daytime";
          description = "";
          trigger = [
            {
              platform = "state";
              entity_id = [ "person.daniel_innes" ];
              to = "home";
            }
          ];
          condition = [
            {
              condition = "numeric_state";
              entity_id = "sensor.central_temperature";
              below = 17.5;
            }
            {
              condition = "time";
              after = "07:00:00";
              before = "21:00:00";
            }
          ];
          action = [
            {
              service = "climate.set_temperature";
              metadata = { };
              data = {
                temperature = 20.5;
              };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1706151134369";
          alias = "Mornings at home (Emma)";
          description = "";
          trigger = [
            {
              platform = "time";
              at = "07:00:00";
            }
          ];
          condition = [
            {
              condition = "state";
              entity_id = "person.emma_l";
              state = "home";
            }
          ];
          action = [
            {
              service = "climate.set_temperature";
              metadata = { };
              data = {
                temperature = 21.5;
              };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1706151237444";
          alias = "Nights at home (Emma)";
          description = "";
          trigger = [
            {
              platform = "time";
              at = "23:00:00";
            }
          ];
          condition = [
            {
              condition = "state";
              entity_id = "person.emma_l";
              state = "home";
            }
          ];
          action = [
            {
              service = "climate.set_temperature";
              metadata = { };
              data = {
                temperature = 18;
              };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1706151407364";
          alias = "Emma increased temperature";
          description = "";
          trigger = [
            {
              platform = "state";
              entity_id = [ "person.emma_l" ];
              to = "home";
            }
          ];
          condition = [
            {
              condition = "numeric_state";
              entity_id = "sensor.central_temperature";
              below = 21;
            }
            {
              condition = "time";
              before = "23:00:00";
            }
          ];
          action = [
            {
              service = "climate.set_temperature";
              metadata = { };
              data = {
                temperature = 21.5;
              };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1706306492854";
          alias = "Off active";
          description = "";
          trigger = [
            {
              platform = "state";
              entity_id = [ "binary_sensor.active_time" ];
              to = "off";
            }
          ];
          condition = [
            {
              condition = "state";
              entity_id = "input_boolean.vacation";
              state = "off";
            }
            {
              condition = "state";
              entity_id = "input_boolean.extended_active_time";
              state = "off";
            }
          ];
          action = [
            {
              service = "climate.set_temperature";
              metadata = { };
              data = {
                temperature = "{{ states('input_number.nighttime_hvac_setpoint') | float }}";
              };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1706306612829";
          alias = "On active";
          description = "";
          trigger = [
            {
              platform = "state";
              entity_id = [ "binary_sensor.active_time" ];
              to = "on";
            }
          ];
          condition = [
            {
              condition = "state";
              entity_id = "input_boolean.vacation";
              state = "off";
            }
            {
              condition = "state";
              entity_id = "input_boolean.extended_active_time";
              state = "off";
            }
          ];
          action = [
            {
              service = "climate.set_temperature";
              metadata = { };
              data = {
                temperature = "{{ states('input_number.daytime_hvac_setpoint') | float }}";
              };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1706306794162";
          alias = "Daniel away";
          description = "";
          trigger = [
            {
              platform = "state";
              entity_id = [ "person.daniel_innes" ];
              to = "not_home";
              for = {
                hours = 8;
                minutes = 0;
                seconds = 0;
              };
            }
          ];
          condition = [
            {
              condition = "state";
              entity_id = "input_boolean.vacation";
              state = "off";
            }
          ];
          action = [
            {
              service = "input_boolean.toggle";
              metadata = { };
              data = { };
              target = {
                entity_id = "input_boolean.vacation";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1706306880252";
          alias = "Daniel home";
          description = "";
          trigger = [
            {
              platform = "state";
              entity_id = [ "person.daniel_innes" ];
              to = "home";
              for = {
                hours = 0;
                minutes = 0;
                seconds = 0;
              };
            }
          ];
          condition = [
            {
              condition = "state";
              entity_id = "input_boolean.vacation";
              state = "on";
            }
          ];
          action = [
            {
              service = "input_boolean.toggle";
              metadata = { };
              data = { };
              target = {
                entity_id = "input_boolean.vacation";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1706307508282";
          alias = "Emma arrival";
          description = "";
          trigger = [
            {
              platform = "state";
              entity_id = [ "person.emma_l" ];
              to = "home";
            }
          ];
          condition = [
            {
              condition = "state";
              entity_id = "input_boolean.extended_active_time";
              state = "off";
            }
          ];
          action = [
            {
              service = "input_boolean.toggle";
              metadata = { };
              data = { };
              target = {
                entity_id = "input_boolean.extended_active_time";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1706307551746";
          alias = "Emma leaves";
          description = "";
          trigger = [
            {
              platform = "state";
              entity_id = [ "person.emma_l" ];
              to = "not_home";
            }
          ];
          condition = [
            {
              condition = "state";
              entity_id = "input_boolean.extended_active_time";
              state = "on";
            }
          ];
          action = [
            {
              service = "input_boolean.toggle";
              metadata = { };
              data = { };
              target = {
                entity_id = "input_boolean.extended_active_time";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1706307744942";
          alias = "Off extended active";
          description = "";
          trigger = [
            {
              platform = "state";
              entity_id = [ "binary_sensor.extended_active_time" ];
              to = "off";
            }
          ];
          condition = [
            {
              condition = "state";
              entity_id = "input_boolean.vacation";
              state = "off";
            }
            {
              condition = "state";
              entity_id = "input_boolean.extended_active_time";
              state = "on";
            }
          ];
          action = [
            {
              service = "climate.set_temperature";
              metadata = { };
              data = {
                temperature = "{{ states('input_number.nighttime_hvac_setpoint') | float }}";
              };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1706307804613";
          alias = "On extended active";
          description = "";
          trigger = [
            {
              platform = "state";
              entity_id = [ "binary_sensor.extended_active_time" ];
              to = "on";
            }
          ];
          condition = [
            {
              condition = "state";
              entity_id = "input_boolean.vacation";
              state = "off";
            }
            {
              condition = "state";
              entity_id = "input_boolean.extended_active_time";
              state = "on";
            }
          ];
          action = [
            {
              service = "climate.set_temperature";
              metadata = { };
              data = {
                temperature = "{{ states('input_number.daytime_hvac_setpoint') | float }}";
              };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1706308043663";
          alias = "On extended active transition";
          description = "";
          trigger = [
            {
              platform = "state";
              entity_id = [ "input_boolean.extended_active_time" ];
              to = "on";
            }
          ];
          condition = [
            {
              condition = "state";
              entity_id = "binary_sensor.active_time";
              state = "off";
            }
            {
              condition = "state";
              entity_id = "binary_sensor.extended_active_time";
              state = "on";
            }
          ];
          action = [
            {
              service = "climate.set_temperature";
              metadata = { };
              data = {
                temperature = "{{ states('input_number.daytime_hvac_setpoint') | float }}";
              };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1706308268483";
          alias = "Off extended active transition";
          description = "";
          trigger = [
            {
              platform = "state";
              entity_id = [ "input_boolean.extended_active_time" ];
              to = "off";
            }
          ];
          condition = [
            {
              condition = "state";
              entity_id = "binary_sensor.active_time";
              state = "off";
            }
            {
              condition = "state";
              entity_id = "binary_sensor.extended_active_time";
              state = "on";
            }
          ];
          action = [
            {
              service = "climate.set_temperature";
              metadata = { };
              data = {
                temperature = "{{ states('input_number.nighttime_hvac_setpoint') | float }}";
              };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1706312058563";
          alias = "On vacation";
          description = "";
          trigger = [
            {
              platform = "state";
              entity_id = [ "input_boolean.vacation" ];
              to = "on";
            }
          ];
          condition = [ ];
          action = [
            {
              service = "climate.set_temperature";
              metadata = { };
              data = {
                temperature = "{{ states('input_number.vacation_hvac_setpoint') | float }}";
              };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
              enabled = false;
            }
            {
              service = "climate.turn_off";
              metadata = { };
              data = { };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1706312299089";
          alias = "Off vacation";
          description = "";
          trigger = [
            {
              platform = "state";
              entity_id = [ "input_boolean.vacation" ];
              to = "off";
            }
          ];
          condition = [
            {
              condition = "or";
              conditions = [
                {
                  condition = "state";
                  entity_id = "binary_sensor.active_time";
                  state = "on";
                }
                {
                  condition = "and";
                  conditions = [
                    {
                      condition = "state";
                      entity_id = "binary_sensor.extended_active_time";
                      state = "on";
                    }
                    {
                      condition = "state";
                      entity_id = "input_boolean.extended_active_time";
                      state = "on";
                    }
                  ];
                }
              ];
            }
          ];
          action = [
            {
              service = "climate.set_temperature";
              metadata = { };
              data = {
                temperature = "{{ states('input_number.daytime_hvac_setpoint') | float }}";
              };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
            }
            {
              service = "climate.turn_on";
              metadata = { };
              data = { };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1707192638207";
          alias = "Min vacation";
          description = "";
          trigger = [
            {
              platform = "numeric_state";
              entity_id = [ "sensor.central_temperature" ];
              below = "input_number.vacation_hvac_min";
            }
          ];
          condition = [
            {
              condition = "state";
              entity_id = "input_boolean.vacation";
              state = "on";
            }
          ];
          action = [
            {
              service = "climate.set_temperature";
              metadata = { };
              data = {
                temperature = "{{ states('input_number.vacation_hvac_setpoint') | float }}";
                hvac_mode = "heat";
              };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
            }
            {
              service = "climate.turn_on";
              metadata = { };
              data = { };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1707192767217";
          alias = "Max vacation";
          description = "";
          trigger = [
            {
              platform = "numeric_state";
              entity_id = [ "sensor.central_temperature" ];
              above = "input_number.vacation_hvac_max";
            }
          ];
          condition = [
            {
              condition = "state";
              entity_id = "input_boolean.vacation";
              state = "on";
            }
          ];
          action = [
            {
              service = "climate.set_temperature";
              metadata = { };
              data = {
                temperature = "{{ states('input_number.vacation_hvac_setpoint') | float }}";
                hvac_mode = "cool";
              };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
            }
            {
              service = "climate.turn_on";
              metadata = { };
              data = { };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1707193239738";
          alias = "Near setpoint vacation ";
          description = "";
          trigger = [
            {
              platform = "numeric_state";
              entity_id = [ "sensor.central_temperature" ];
              above = "input_number.vacation_hvac_min_setpoint";
              below = "input_number.vacation_hvac_max_setpoint";
            }
          ];
          condition = [
            {
              condition = "state";
              entity_id = "input_boolean.vacation";
              state = "on";
            }
          ];
          action = [
            {
              service = "climate.turn_off";
              metadata = { };
              data = { };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
            }
          ];
          mode = "single";
        }
        {
          id = "1707193735954";
          alias = "Off vacation night";
          description = "";
          trigger = [
            {
              platform = "state";
              entity_id = [ "input_boolean.vacation" ];
              to = "off";
            }
          ];
          condition = [
            {
              condition = "or";
              conditions = [
                {
                  condition = "state";
                  entity_id = "binary_sensor.active_time";
                  state = "off";
                }
                {
                  condition = "and";
                  conditions = [
                    {
                      condition = "state";
                      entity_id = "binary_sensor.extended_active_time";
                      state = "off";
                    }
                    {
                      condition = "state";
                      entity_id = "input_boolean.extended_active_time";
                      state = "on";
                    }
                  ];
                }
              ];
            }
          ];
          action = [
            {
              service = "climate.set_temperature";
              metadata = { };
              data = {
                temperature = "{{ states('input_number.nighttime_hvac_setpoint') | float }}";
              };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
            }
            {
              service = "climate.turn_on";
              metadata = { };
              data = { };
              target = {
                device_id = "78d0f05b3f230281a0b3ad1fc8f8c8f3";
              };
            }
          ];
          mode = "single";
        }
      ];
      http = {
        use_x_forwarded_for = true;
        trusted_proxies = [
          "127.0.0.1"
          "10.8.8.8"
          "172.30.33.0/24"
        ];
      };
      prometheus = {
        namespace = "hass";
      };
      device_tracker = [
        {
          platform = "snmp";
          host = "10.8.8.1";
          community = "wgy5cFFF4qLqfY4YYsW2MzyyfRk7Jh9V";
          baseoid = "1.3.6.1.2.1.4.22.1.2";
        }
      ];
      sensor = [
        {
          platform = "metar";
          airport_name = "Ottawa";
          airport_code = "CYOW";
        }
        {
          platform = "statistics";
          name = "Central hvac load";
          entity_id = "binary_sensor.central_running";
          state_characteristic = "average_step";
          max_age = {
            days = 1;
          };
        }
        {
          platform = "statistics";
          name = "Central hvac load short term";
          entity_id = "binary_sensor.central_running";
          state_characteristic = "average_step";
          max_age = {
            hours = 3;
          };
        }
        {
          platform = "statistics";
          name = "Central hvac on count";
          entity_id = "binary_sensor.central_running";
          state_characteristic = "count_on";
          max_age = {
            days = 1;
          };
        }
        {
          platform = "statistics";
          name = "Mean temp over a day";
          entity_id = "sensor.ottawa_kanata_orleans_temperature";
          state_characteristic = "average_linear";
          max_age = {
            days = 1;
          };
        }
        {
          platform = "statistics";
          name = "Central hvac max temp delta";
          entity_id = "sensor.central_hvac_temp_delta";
          state_characteristic = "value_max";
          max_age = {
            days = 1;
          };
        }
        {
          platform = "statistics";
          name = "Central hvac min temp delta";
          entity_id = "sensor.central_hvac_temp_delta";
          state_characteristic = "value_min";
          max_age = {
            days = 1;
          };
        }
        {
          platform = "snmp";
          host = "10.8.8.19";
          port = 161;
          community = "S7E3cTonjQyQ75AiM85UqMJQz";
          name = "raw_dell_server_power";
          baseoid = "1.3.6.1.4.1.674.10892.5.4.600.30.1.6.1.3";
          unit_of_measurement = "W";
        }
        {
          platform = "snmp";
          host = "10.8.8.19";
          port = 161;
          community = "S7E3cTonjQyQ75AiM85UqMJQz";
          name = "raw_dell_server_psu1_current";
          baseoid = "1.3.6.1.4.1.674.10892.5.4.600.30.1.6.1.1";
          unit_of_measurement = "A";
          value_template = "{{((value | float) / 10) | float}}";
        }
        {
          platform = "snmp";
          host = "10.8.8.19";
          port = 161;
          community = "S7E3cTonjQyQ75AiM85UqMJQz";
          name = "raw_dell_server_psu2_current";
          baseoid = "1.3.6.1.4.1.674.10892.5.4.600.30.1.6.1.2";
          unit_of_measurement = "A";
          value_template = "{{((value | float) / 10) | float}}";
        }
        {
          platform = "snmp";
          host = "10.8.8.19";
          port = 161;
          community = "S7E3cTonjQyQ75AiM85UqMJQz";
          name = "raw_dell_server_psu1_voltage";
          baseoid = "1.3.6.1.4.1.674.10892.5.4.600.20.1.6.1.26";
          unit_of_measurement = "V";
          value_template = "{{((value | float) / 1000) | float}}";
        }
        {
          platform = "snmp";
          host = "10.8.8.19";
          port = 161;
          community = "S7E3cTonjQyQ75AiM85UqMJQz";
          name = "raw_dell_server_psu2_voltage";
          baseoid = "1.3.6.1.4.1.674.10892.5.4.600.20.1.6.1.27";
          unit_of_measurement = "V";
          value_template = "{{((value | float) / 1000) | float}}";
        }
        {
          platform = "snmp";
          host = "10.8.8.19";
          port = 161;
          community = "S7E3cTonjQyQ75AiM85UqMJQz";
          name = "raw_dell_server_inlet_temperature";
          baseoid = "1.3.6.1.4.1.674.10892.5.4.700.20.1.6.1.1";
          unit_of_measurement = "°C";
          value_template = "{{((value | float) / 10) | float}}";
        }
        {
          platform = "snmp";
          host = "10.8.8.19";
          port = 161;
          community = "S7E3cTonjQyQ75AiM85UqMJQz";
          name = "raw_dell_server_exhaust_temperature";
          baseoid = "1.3.6.1.4.1.674.10892.5.4.700.20.1.6.1.2";
          unit_of_measurement = "°C";
          value_template = "{{((value | float) / 10) | float}}";
        }
        {
          platform = "snmp";
          host = "10.8.8.19";
          port = 161;
          community = "S7E3cTonjQyQ75AiM85UqMJQz";
          name = "raw_dell_server_cpu1_temperature";
          baseoid = "1.3.6.1.4.1.674.10892.5.4.700.20.1.6.1.3";
          unit_of_measurement = "°C";
          value_template = "{{((value | float) / 10) | float}}";
        }
        {
          platform = "snmp";
          host = "10.8.8.19";
          port = 161;
          community = "S7E3cTonjQyQ75AiM85UqMJQz";
          name = "raw_dell_server_cpu2_temperature";
          baseoid = "1.3.6.1.4.1.674.10892.5.4.700.20.1.6.1.4";
          unit_of_measurement = "°C";
          value_template = "{{((value | float) / 10) | float}}";
        }
        {
          platform = "snmp";
          host = "10.8.8.19";
          port = 161;
          community = "S7E3cTonjQyQ75AiM85UqMJQz";
          name = "raw_dell_server_virtual_disk_state";
          baseoid = "1.3.6.1.4.1.674.10892.5.5.1.20.140.1.1.4.1";
        }
        {
          platform = "snmp";
          host = "10.8.8.19";
          port = 161;
          community = "S7E3cTonjQyQ75AiM85UqMJQz";
          name = "raw_dell_server_fan1";
          baseoid = "1.3.6.1.4.1.674.10892.5.4.700.12.1.6.1.1";
          unit_of_measurement = "RPM";
        }
        {
          platform = "snmp";
          host = "10.8.8.19";
          port = 161;
          community = "S7E3cTonjQyQ75AiM85UqMJQz";
          name = "raw_dell_server_fan2";
          baseoid = "1.3.6.1.4.1.674.10892.5.4.700.12.1.6.1.2";
          unit_of_measurement = "RPM";
        }
        {
          platform = "snmp";
          host = "10.8.8.19";
          port = 161;
          community = "S7E3cTonjQyQ75AiM85UqMJQz";
          name = "raw_dell_server_fan3";
          baseoid = "1.3.6.1.4.1.674.10892.5.4.700.12.1.6.1.3";
          unit_of_measurement = "RPM";
        }
        {
          platform = "snmp";
          host = "10.8.8.19";
          port = 161;
          community = "S7E3cTonjQyQ75AiM85UqMJQz";
          name = "raw_dell_server_fan4";
          baseoid = "1.3.6.1.4.1.674.10892.5.4.700.12.1.6.1.4";
          unit_of_measurement = "RPM";
        }
        {
          platform = "snmp";
          host = "10.8.8.19";
          port = 161;
          community = "S7E3cTonjQyQ75AiM85UqMJQz";
          name = "raw_dell_server_fan5";
          baseoid = "1.3.6.1.4.1.674.10892.5.4.700.12.1.6.1.5";
          unit_of_measurement = "RPM";
        }
        {
          platform = "snmp";
          host = "10.8.8.19";
          port = 161;
          community = "S7E3cTonjQyQ75AiM85UqMJQz";
          name = "raw_dell_server_fan6";
          baseoid = "1.3.6.1.4.1.674.10892.5.4.700.12.1.6.1.6";
          unit_of_measurement = "RPM";
        }
        {
          platform = "integration";
          source = "sensor.server_power";
          name = "Dell Server Energy";
          unit_prefix = "k";
          unit_time = "h";
          round = 2;
        }
      ];
      template = [
        {
          sensor = [
            {
              name = "central_hvac_temp_delta";
              state = "{{ (states('sensor.hvac_temp_delta_temperature') | float) - (states('sensor.hvac_temp_delta_temperature_return') | float)}}";
              unit_of_measurement = "°C";
              device_class = "temperature";
              state_class = "measurement";
            }
            {
              name = "central_hvac_load_per_cycle";
              state = "{{ ((states('sensor.central_hvac_load') | float) / (states('sensor.central_hvac_on_count') | float)) | round(2) }}";
              state_class = "measurement";
            }
            {
              name = "central_hvac_degrees_per_load";
              state = "{{ (((states('sensor.central_temperature') | float) - (states('sensor.mean_temp_over_a_day') | float) | abs ) / (states('sensor.central_hvac_load') | float)) | round(2)}}";
              unit_of_measurement = "°C/unit";
              state_class = "measurement";
            }
            {
              name = "Server Power";
              state = "{{states('sensor.raw_dell_server_power')}}";
              unit_of_measurement = "W";
              device_class = "power";
              state_class = "measurement";
            }
            {
              name = "Server Inlet Temperature";
              state = "{{states('sensor.raw_dell_server_inlet_temperature')}}";
              unit_of_measurement = "°C";
              device_class = "temperature";
              state_class = "measurement";
            }
            {
              name = "Server Exhaust Temperature";
              state = "{{states('sensor.raw_dell_server_exhaust_temperature')}}";
              unit_of_measurement = "°C";
              device_class = "temperature";
              state_class = "measurement";
            }
            {
              name = "Server CPU1 Temperature";
              state = "{{states('sensor.raw_dell_server_cpu1_temperature')}}";
              unit_of_measurement = "°C";
              device_class = "temperature";
              state_class = "measurement";
            }
            {
              name = "Server CPU2 Temperature";
              state = "{{states('sensor.raw_dell_server_cpu2_temperature')}}";
              unit_of_measurement = "°C";
              device_class = "temperature";
              state_class = "measurement";
            }
            {
              name = "Server Virtual Disk State";
              state = "{% set mapper =  {\n  '1' : 'Unknown',\n  '2' : 'Online',\n  '3' : 'Failed',\n  '4' : 'Degraded' } %}\n{% set state =  states.sensor.raw_dell_server_virtual_disk_state.state %} {{ mapper[state] | default('unknown') }}";
            }
            {
              name = "Server Fans Speed Avg";
              state = "{{ (( states('sensor.raw_dell_server_fan1') | float +\n      states('sensor.raw_dell_server_fan2') | float +\n      states('sensor.raw_dell_server_fan3') | float +\n      states('sensor.raw_dell_server_fan4') | float +\n      states('sensor.raw_dell_server_fan5') | float +\n      states('sensor.raw_dell_server_fan6') | float) / 6) | round(0) }}\n";
              unit_of_measurement = "RPM";
              icon = "mdi:fan";
            }
          ];
        }
      ];
    };
  };
}
