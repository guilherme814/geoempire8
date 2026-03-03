AREAS = {
    "brasil": {
        "coords": [(200,300), (250,320), (240,370), (190,350)],
        "owner": "player",
        "troops": 10
    },
    "argentina": {
        "coords": [(180,370), (230,420), (170,450)],
        "owner": "enemy",
        "troops": 6
    }
}



with self.canvas:
    self.map_texture = Rectangle(
        source="assets/images/map.png",
        pos=self.pos,
        size=self.size
    )



Color(1, 0, 0, 0.4)
Line(points=polygon_points, close=True, width=2)