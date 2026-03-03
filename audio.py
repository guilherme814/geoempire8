from kivy.core.audio import SoundLoader

class AudioManager:
    def __init__(self):
        self.click = SoundLoader.load("assets/sounds/click.wav")
        self.battle = SoundLoader.load("assets/sounds/battle.wav")
        self.bg = SoundLoader.load("assets/sounds/background.mp3")

    def play_click(self):
        if self.click:
            self.click.play()

    def play_battle(self):
        if self.battle:
            self.battle.play()

    def play_bg(self):
        if self.bg:
            self.bg.loop = True
            self.bg.play()