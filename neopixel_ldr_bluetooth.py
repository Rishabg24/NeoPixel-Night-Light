import time 
import board 
import neopixel
import random
import digitalio
import keypad
from analogio import AnalogIn
from adafruit_ble import BLERadio
from adafruit_ble.advertising.standard import ProvideServicesAdvertisement
from adafruit_ble.services.nordic import UARTService
from adafruit_bluefruit_connect.packet import Packet
from adafruit_bluefruit_connect.button_packet import ButtonPacket
from adafruit_bluefruit_connect.color_packet import ColorPacket

# ===== Configuration ===== 
# change these to match your wiring 
LDR_PIN = board.A3 # analog pin connected to LDR voltage divider 
LDR_POWER_PIN = board.D4 # digital pin that provides Vcc to the LDR divider 
NORMALIZED_THRESHOLD = 0.4
keys = keypad.Keys(
    (board.D9,), value_when_pressed = False, pull = True)

# ===== Setup =====
ldr_in = AnalogIn(LDR_PIN)
ldr_power = digitalio.DigitalInOut(LDR_POWER_PIN)
ldr_power.direction = digitalio.Direction.OUTPUT
# turn on power to LDR voltage divider
ldr_power.value = True

pixel_pin = board.D7
num_pixels = 2
ORDER = neopixel.GRB

pixels = neopixel.NeoPixel(
   pixel_pin,
   num_pixels,
   brightness=.3,
   auto_write=False,
   pixel_order=ORDER
)

def connect_blue(name):
    ble.name = name
    advertisement = ProvideServicesAdvertisement(uart)
    ble.start_advertising(advertisement)
    while not ble.connected:
        pass
    print("connected!")
    time.sleep(1)

def random_color():
    R = random.randint(0, 255)
    G = random.randint(0, 255)
    B = random.randint(0, 255)
    color = (R, G, B)
    return color
    

def normalized_read(value):
    return value / 65535


neopixel_on = False
override = False
color = random_color()
smooth_mode = False
brightness_direction = 1  # 1 for increasing, -1 for decreasing
smooth_brightness = 0.3
brightness_step = 0.01
last_smooth_update = time.monotonic()

try:
    ble = BLERadio()
    uart = UARTService()
    connect_blue(" RG ")
    while True:
        raw = ldr_in.value
        val = normalized_read(raw)
        event = keys.events.get()
        
        #print("raw:", raw, " normalized:", val, " override:", override, " neopixel_on:", neopixel_on)
        if ble.connected and uart.in_waiting:
            packet = Packet.from_stream(uart)
            if isinstance(packet, ColorPacket):
                color = packet.color
                print("New color:", color)
                # If light is currently on, update it immediately
                if neopixel_on:
                    pixels.fill(color)
                    pixels.show()
                    
            if isinstance(packet, ButtonPacket) and packet.pressed:
                if packet.button == ButtonPacket.BUTTON_1:
                    smooth_mode = not smooth_mode
                    print("Smoothing Mode:", "Enabled" if smooth_mode else "Disabled")
                    if smooth_mode:
                        neopixel_on = True
                        smooth_brightness = 0.1
                        brightness_direction = 1
                        color = random_color()
                        pixels.fill(color)
                        pixels.brightness = smooth_brightness
                        pixels.show()
                    else:
                        # Return to normal mode with current color
                        pixels.brightness = 0.3
                        pixels.fill(color)
                        pixels.show()
                        
                elif packet.button == ButtonPacket.UP:
                    if not smooth_mode:
                        pixels.brightness = min(1.0, pixels.brightness + 0.1)
                        print("UP! Brightness:", pixels.brightness)
                        if neopixel_on:
                            pixels.show()
                        
                elif packet.button == ButtonPacket.DOWN:
                    if not smooth_mode:
                        pixels.brightness = max(0.0, pixels.brightness - 0.1)
                        print("DOWN! Brightness:", pixels.brightness)
                        if neopixel_on:
                            pixels.show()
                    
        # Handle button press
        if event and event.pressed:
            if not smooth_mode:
                override = not override
                print("Override toggled to:", override)
               
                if override:
                    neopixel_on = not neopixel_on
                    if neopixel_on:
                        pixels.fill(color)
                    else:
                        pixels.fill((0, 0, 0))
                    pixels.show()
        
        if smooth_mode:
            current_time = time.monotonic()
            if current_time - last_smooth_update >= 0.05:  # Update every 50ms
                last_smooth_update = current_time
                
                # Update brightness
                smooth_brightness += brightness_direction * brightness_step
                
                # Check if we need to reverse direction
                if smooth_brightness >= 1.0:
                    smooth_brightness = 1.0
                    brightness_direction = -1
                elif smooth_brightness <= 0.05:
                    smooth_brightness = 0.05
                    brightness_direction = 1
                    # Change color at the bottom of the cycle
                    color = random_color()
                    print("New smooth color:", color)
                
                pixels.brightness = smooth_brightness
                pixels.fill(color)
                pixels.show()
        
        # Normal sensor-based operation (only when not in override or smooth mode)
        elif not override:
            # Dark detected - turn on light
            if val > NORMALIZED_THRESHOLD and not neopixel_on:
                pixels.fill(color)
                pixels.show()
                neopixel_on = True
                print("Light turned ON (dark detected)")
         
            # Light detected - turn off light
            elif val < NORMALIZED_THRESHOLD and neopixel_on:
                pixels.fill((0, 0, 0))
                pixels.show()
                neopixel_on = False
                print("Light turned OFF (light detected)")
        
        time.sleep(0.01)  # Reduced for smoother animation
          
except KeyboardInterrupt:
    pixels.fill((0, 0, 0))
    pixels.show()