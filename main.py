from kivy.app import App
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.label import Label
from kivy.uix.button import Button

class HHG729App(App):
    def build(self):
        layout = BoxLayout(orientation="vertical")

        title = Label(
            text="HHG729 - Jogo de Estratégia",
            font_size=32
        )

        button = Button(
            text="Iniciar",
            font_size=24
        )

        layout.add_widget(title)
        layout.add_widget(button)

        return layout

if __name__ == "__main__":
    HHG729App().run()