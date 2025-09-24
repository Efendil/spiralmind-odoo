from odoo import models, fields

class ShipmentVehicle(models.Model):
    _name = "shipment.vehicle"
    _description = "Shipment Vehicle"

    name = fields.Char(string="Vehicle Name", required=True)
    secured = fields.Boolean(string="Secured")
    express = fields.Boolean(string="Express")
    category_ids = fields.Many2many('shipment.vehicle.category',string="Tags")