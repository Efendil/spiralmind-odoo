from odoo import models, fields, api

class SaleOrderLine(models.Model):
    _inherit = 'sale.order.line'


    weight = fields.Float(string='Weight')
    lademeter = fields.Float(string='Lademeter', compute="_compute_lademeter", store=True, digits=(16, 1))
    volume = fields.Float(string='Volume', compute="_compute_volume", store=True, digits=(16, 2))

    @api.depends('weight')
    def _compute_lademeter(self):
        for rec in self:
            rec.lademeter = rec.weight / 700 if rec.weight else 0

    @api.depends('weight')
    def _compute_volume(self):
        for rec in self:
            rec.volume = rec.weight / 166.66 if rec.weight else 0