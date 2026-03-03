class GameState:
    def __init__(self):
        self.player_gold = 100
        self.turn = 1
        self.selected_area = None

    def attack(self, origin, target):
        if origin["troops"] > target["troops"]:
            target["owner"] = "player"
            target["troops"] = origin["troops"] - 1
        else:
            origin["troops"] -= 1