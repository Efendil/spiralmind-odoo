from odoo import models, fields, api
from itertools import product

class PricingScale(models.Model):
    _name = 'pricing.scale'

    cost = fields.Float(string='Cost' )
    distance_interval = fields.Selection([
        ('1', 'Until 50'),
        ('2', 'Until 150'),
        ('3', 'Until 275'),
        ('4', 'Until 550'),
        ('5', 'Above 550'),
    ],
        "Distance interval", required=True
    )
    max_height = fields.Selection([
        ('1', 'Until 220'),
        ('2', 'Until 260'),
        ('3', 'Until 300'),
        ('4', 'Above 300'),

    ],
        "Max height", required=True
    )
    weight_kg = fields.Float(string='Weight')
    lademeter = fields.Float(string='Lademeter', compute="_compute_lademeter", store=True, digits=(16, 1))

    @api.depends('weight_kg')
    def _compute_lademeter(self):
        for rec in self:
            rec.lademeter = rec.weight_kg / 700 if rec.weight_kg else 0

    @api.model
    def generate_combinations(self):
        distance_vals = ['1', '2', '3', '4', '5']
        weights_by_height = {
            '1': [1000],
            '2': [1500, 2000, 2500, 3000, 4000, 5000, 7000, 9000],
            '3': [11000, 14000, 17000, 20000, 23600],
        }

        for dist, height in product(distance_vals, weights_by_height.keys()):
            for weight in weights_by_height[height]:
                exists = self.search([
                    ('distance_interval', '=', dist),
                    ('max_height', '=', height),
                    ('weight_kg', '=', weight),
                ], limit=1)

                if not exists:
                    self.create({
                        'distance_interval': dist,
                        'max_height': height,
                        'weight_kg': weight,
                        'cost': 0.0,
                    })