from odoo import models, fields, api

class SaleOrder(models.Model):
    _inherit = 'sale.order'



    shipment_type = fields.Selection([
        ('import', 'Import'),
        ('export', 'Export'),
    ], "Shipment type")

    zip_destination = fields.Char(string='ZIP')
    distance = fields.Float(string='Distance')


