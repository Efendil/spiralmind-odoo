from odoo import fields, models, api

class ResPartner(models.Model):
    _inherit = "res.partner"

    order_ref = fields.Char('Order efrence', help="Customer reference for orders")
    gha = fields.Boolean(string="GHA")
    warehouse = fields.Boolean(string="Warehouse")
    company_ids = fields.Many2many('res.partner',
        'res_partner_company_rel',
        'partner_id',
        'company_id',
        string="Pickup/Delivery Companies",
        tracking=True)

    def _compute_display_name(self):
        super()._compute_display_name()
        show_ref = self.env.context.get("show_ref", False)
        for rec in self:
            if show_ref:
                rec.display_name = rec.ref or rec.name or ''
            else:
                rec.display_name = rec.name or ''


