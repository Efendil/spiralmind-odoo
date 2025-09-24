from odoo import models, fields, api, _
from odoo.exceptions import ValidationError



class ShipmentLine(models.Model):
    _name = "shipment.line"
    _description = "Shipment Line"

    shipment_id = fields.Many2one('shipment.management', string="Shipment", required=True, ondelete='cascade')
    description = fields.Char(string="Description", required=True)
    quantity = fields.Integer(string="Quantity", default=1)
    weight = fields.Float(string="Weight (kg)", digits='Product Unit of Measure')
    volume = fields.Float(string="Volume (m³)", digits=(16, 3))
    length_cm = fields.Float(string="Length (cm)")
    width_cm = fields.Float(string="Width (cm)")
    height_cm = fields.Float(string="Height (cm)")
    price_unit = fields.Float(string="Unit Price", digits="Product Price")

    @api.constrains('quantity')
    def _check_quantity_positive(self):
        for rec in self:
            if rec.quantity and rec.quantity < 1:
                raise ValidationError(_("Quantity must be at least 1."))
