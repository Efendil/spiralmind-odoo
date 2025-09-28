# -*- coding: utf-8 -*-
from odoo import fields, models

class PostalCode(models.Model):
    _name = 'postal.code'

    name = fields.Char('ZIP', help="ZIP number")
    zone = fields.Selection(
        [("1", "1"), ("2", "2")],
        string="Zone",
    )
    code = fields.Char(string="Code")
    city = fields.Char(string="City", required=True)