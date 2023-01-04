import uiautomator2 as u
import os , time , pyperclip

class transfer:
    def run(self):
        while True:
            t = self.main()
            d.clipboard = t
            d2.clipboard = t

    def main(self):
        recent_txt = pyperclip.paste()
        while True:
            os.system('adb connect 192.168.31.15:6666')
            os.system('adb connect 192.168.31.211:4444')
            txt = pyperclip.paste()
            if txt != recent_txt:
                recent_txt = txt
                return recent_txt
            time.sleep(0.2)

os.system('adb connect 192.168.31.15:6666')
os.system('adb connect 192.168.31.211:4444')
d = u.connect('192.168.31.15:6666')
d2 = u.connect('192.168.31.211:4444')

transfer().run()