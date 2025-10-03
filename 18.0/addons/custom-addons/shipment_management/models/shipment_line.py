from odoo import models, fields, api, _
from odoo.exceptions import ValidationError



class ShipmentLine(models.Model):
    _name = "shipment.line"
    _description = "Shipment Line"

    shipment_id = fields.Many2one('shipment.management', string="Shipment", required=True, ondelete='cascade')
    quantity = fields.Integer(string="Quantity", default=1)
    weight = fields.Float(string="Weight (kg)", digits='Product Unit of Measure')
    volume = fields.Float(string="Volume (m³)", digits=(16, 3), compute="_compute_volume",store=True, readonly=False)
    length_cm = fields.Float(string="Length (cm)")
    width_cm = fields.Float(string="Width (cm)")
    height_cm = fields.Float(string="Height (cm)")
    price_unit = fields.Float(string="Unit Price", digits="Product Price")
    chargeable_weight = fields.Float(string="Chargeable Weight (kg)",compute="_compute_chargeable_weight",store=True,
                                     readonly=False)
    volumetric_weight = fields.Float(string="Volumetric Weight (kg)", compute="_compute_chargeable_weight",store=True)

    @api.constrains('quantity')
    def _check_quantity_positive(self):
        for rec in self:
            if rec.quantity and rec.quantity < 1:
                raise ValidationError(_("Quantity must be at least 1."))

    @api.depends('length_cm', 'width_cm', 'height_cm')
    def _compute_volume(self):
        for rec in self:
            if rec.length_cm and rec.width_cm and rec.height_cm:
                rec.volume = (rec.length_cm/100 * rec.width_cm /100 * rec.height_cm/100)
            else:
                rec.volume = 0.0

    @api.depends('length_cm', 'width_cm', 'height_cm', 'weight','volume','shipment_id.loading_meter')
    def _compute_chargeable_weight(self):
        for rec in self:
            volumetric_weight = 0.0
            if rec.length_cm and rec.width_cm and rec.height_cm:
                volumetric_weight = (rec.length_cm * rec.width_cm * rec.height_cm) / 6000
            elif rec.volume:
                volumetric_weight = rec.volume * 1000000 / 6000
            loading_meter = rec.shipment_id.loading_meter or 0
            l_weight = loading_meter * 700
            rec.volumetric_weight = volumetric_weight
            rec.chargeable_weight = max(rec.weight or 0.0, volumetric_weight, l_weight)
