from odoo import fields, models, api,_
from odoo.exceptions import ValidationError

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

    @api.constrains('zip', 'country_id')
    def _check_zip_germany(self):
        for rec in self:
            if rec.country_id and rec.country_id.code == 'DE':
                if not rec.zip or len(rec.zip) != 5 or not rec.zip.isdigit():
                    raise ValidationError(
                        _("In Germany, the ZIP code must contain exactly 5 digits.")
                    )


