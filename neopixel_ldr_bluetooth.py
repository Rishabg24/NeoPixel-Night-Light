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
from adafruit_led_animation.animation.blink import Blink
from adafruit_led_animation.animation.chase import Chase
from adafruit_led_animation.animation.comet import Comet
from adafruit_led_animation.color import RED, AMBER, JADE, PURPLE
from adafruit_led_animation.sequence import AnimationSequence  

# ===== Configuration =====
LDR_PIN = board.A3
LDR_POWER_PIN = board.D4
NORMALIZED_THRESHOLD = 0.4
BLE_NAME = "RG-Nightlight"

keys = keypad.Keys((board.D9,), value_when_pressed=False, pull=True)

# ===== Setup =====
ldr_in = AnalogIn(LDR_PIN)
ldr_power = digitalio.DigitalInOut(LDR_POWER_PIN)
ldr_power.direction = digitalio.Direction.OUTPUT
ldr_power.value = True

pixel_pin = board.D7
num_pixels = 2
ORDER = neopixel.GRB

pixels = neopixel.NeoPixel(
    pixel_pin,
    num_pixels,
    brightness=0.3,
    auto_write=False,
    pixel_order=ORDER
)

blink = Blink(pixels, speed=0.5, color=RED)
comet = Comet(pixels, speed=0.01, color=PURPLE, tail_length=10, bounce=True)
chase = Chase(pixels, speed=0.1, size=3, spacing=6, color=AMBER)

animations = AnimationSequence(blink, comet, chase, advance_interval=3, auto_clear=True)

def random_color():
    return (random.randint(0, 255), random.randint(0, 255), random.randint(0, 255))

def start_ble_advertising():
    try:
        if ble.connected: return
        if not ble.advertising:
            advertisement = ProvideServicesAdvertisement(uart)
            ble.start_advertising(advertisement)
            print(f"BLE advertising as '{BLE_NAME}'")
    except Exception as e:
        print("Advertising error:", e)

def normalized_read(value):
    return value / 65535

# State variables
neopixel_on = False
override = False
color = random_color()
smooth_mode = False
brightness_direction = 1
smooth_brightness = 0.3
brightness_step = 0.01
last_smooth_update = time.monotonic()
last_ble_check = time.monotonic()

# Initialize BLE
ble = BLERadio()
ble.name = BLE_NAME
uart = UARTService()

print("Nightlight starting...")
start_ble_advertising()

try:
    while True:
        #animations.animate()
        current_time = time.monotonic()

        # 1. Connection Management
        if current_time - last_ble_check >= 1.0:
            last_ble_check = current_time
            if not ble.connected and not ble.advertising:
                start_ble_advertising()

        # 2. Read Sensors
        raw = ldr_in.value
        val = normalized_read(raw)
        event = keys.events.get()

        # 3. Handle BLE Packets
        if ble.connected and uart.in_waiting:
            try:
                # Packet.from_stream can raise ValueError if checksum fails
                packet = Packet.from_stream(uart)

                if isinstance(packet, ColorPacket):
                    color = packet.color
                    print("New color:", color)
                    if neopixel_on and not smooth_mode:
                        pixels.fill(color)
                        pixels.show()

                elif isinstance(packet, ButtonPacket) and packet.pressed:
                    if packet.button == ButtonPacket.BUTTON_1:
                        smooth_mode = not smooth_mode
                        print(f"Smooth Mode: {smooth_mode}")
                        if smooth_mode:
                            neopixel_on = True
                            smooth_brightness = 0.1
                            color = random_color()
                        else:
                            pixels.brightness = 0.3
                            pixels.fill(color)
                            pixels.show()
                    
                    elif packet.button == ButtonPacket.UP:
                        if not smooth_mode:
                            pixels.brightness = min(1.0, pixels.brightness + 0.1)
                            print(f"Brightness UP: {pixels.brightness:.2f}")
                            if neopixel_on: pixels.show()

                    elif packet.button == ButtonPacket.DOWN:
                        if not smooth_mode:
                            pixels.brightness = max(0.05, pixels.brightness - 0.1)
                            print(f"Brightness DOWN: {pixels.brightness:.2f}")
                            if neopixel_on: pixels.show()

            except ValueError:
                # Catching any checksum errors while still allowing the loop continues
                print("Ignored bad packet (checksum error)")
                raw = uart.read(uart.in_waiting)
                print("Ignored bad packet (raw):", raw)
                if raw:
                    print([hex(b) for b in raw])
            except Exception as e:
                print(f"Packet error: {e}")

        # 4. Handle Physical Button
        if event and event.pressed:
            if not smooth_mode:
                override = not override
                print(f"Override: {override}")
                neopixel_on = override
                if neopixel_on:
                    pixels.fill(color)
                else:
                    pixels.fill((0, 0, 0))
                pixels.show()

        # 5. Smooth Mode Animation
        if smooth_mode:
            if current_time - last_smooth_update >= 0.05:
                last_smooth_update = current_time
                smooth_brightness += brightness_direction * brightness_step

                if smooth_brightness >= 1.0:
                    smooth_brightness = 1.0
                    brightness_direction = -1
                elif smooth_brightness <= 0.05:
                    smooth_brightness = 0.05
                    brightness_direction = 1
                    color = random_color()
                
                pixels.brightness = smooth_brightness
                pixels.fill(color)
                pixels.show()

        # 6. Automatic LDR Control
        elif not override:
            if val > NORMALIZED_THRESHOLD and not neopixel_on:
                pixels.fill(color)
                pixels.show()
                neopixel_on = True
                print("Auto-ON (Dark)")
            elif val < NORMALIZED_THRESHOLD and neopixel_on:
                pixels.fill((0, 0, 0))
                pixels.show()
                neopixel_on = False
                print("Auto-OFF (Light)")

        time.sleep(0.01)

except KeyboardInterrupt:
    pixels.fill((0, 0, 0))
    pixels.show()
    print("Stopped")
