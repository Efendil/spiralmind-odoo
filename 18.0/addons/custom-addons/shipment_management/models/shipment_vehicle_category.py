from odoo import models, fields

class ShipmentVehicleCategory(models.Model):
    _name = "shipment.vehicle.category"
    _description = "Shipment Vehicle category"

    name = fields.Char(string="Name", required=True)
    color = fields.Integer(string="Color")