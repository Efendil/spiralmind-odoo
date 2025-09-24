from odoo import api, SUPERUSER_ID

def initialize_pricing_scale(env):
    env['pricing.scale'].generate_combinations()