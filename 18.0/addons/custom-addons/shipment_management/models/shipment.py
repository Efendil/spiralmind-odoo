
from odoo import models, fields, api, _
from odoo.exceptions import ValidationError
from datetime import datetime, timedelta



class Shipment(models.Model):
    _name = "shipment.management"
    _description = "Shipment Import/Export"
    _inherit = ["mail.thread", "mail.activity.mixin"]
    _order = "id desc"

    # Unique reference number
    reference = fields.Char(
        copy=False,
        readonly=False,
        index=True,
        default="New",
        tracking=True,
        required=True
    )
    shipment_type = fields.Selection(
        [("import", "Import"), ("export", "Export")],
        string="Shipment Type",
        required=True,
    )
    company_id = fields.Many2one(
        'res.company',
        string='Company',
        required=True,
        default=lambda self: self.env.company,
    )
    customer_id = fields.Many2one('res.partner', string='Customer',required=True,
                                  domain=[('ref', '!=', False)],tracking=True)
    ref_customer = fields.Char(string="Customer reference", compute='_compute_ref_customer',
                               store=False, readonly=False,tracking=True,required=True)
    delivery_company_id = fields.Many2one('res.partner', string="Pickup/Delivery Company", required=True,tracking=True)
    domain_delivery_company_id = fields.Binary(compute="_compute_domain_delivery_company_id", readonly=True)
    loading_time_from = fields.Float(string="From", tracking=True)
    loading_time_to = fields.Float(string="To", tracking=True)
    loading_time = fields.Char(string="Loading Time", compute="_compute_loading_time", store=False)
    zip_code = fields.Many2one('postal.code',string="ZIP code",tracking=True,required=True)
    city = fields.Char(string="City",related="zip_code.city",store=False,eadonly=True,required=True)
    postal_code_code = fields.Char(string="Postal Code",related="zip_code.code",store=True,readonly=True)
    total_quantity = fields.Integer(string="Total Quantity", compute='_compute_totals', store=True)
    total_weight = fields.Float(string="Total Weight (kg)", compute='_compute_totals', store=True,
                                digits='Product Unit of Measure')
    total_volume = fields.Float(string="Total Volume (m³)", compute='_compute_totals', store=True, digits=(16, 3))
    total_chargeable_weight = fields.Float(string="Chargeable weight", compute='_compute_totals', store=True,
                                digits='Product Unit of Measure')
    total_price = fields.Float(string="Total Price",compute="_compute_totals",store=True,digits="Product Price")
    entry_date = fields.Date(string="Entry Date", default=fields.Date.context_today, readonly=True)
    order_date = fields.Date(string="Order Date", tracking=True,  readonly=False,
                             default=lambda self: fields.Date.to_string(datetime.now().date() + timedelta(days=1)))
    line_ids = fields.One2many('shipment.line', 'shipment_id', string="Shipment Lines",tracking=True)
    document_ids = fields.Many2many('ir.attachment', string="Documents",tracking=True)
    notes = fields.Text(string="Notes",tracking=True)
    shipment_type_display = fields.Char(string="Type",compute="_compute_shipment_type_display",
                                        store=False,tracking=True)
    vehicle_id = fields.Many2one('shipment.vehicle',string="Vehicle",tracking=True)
    state = fields.Selection([
        ('draft', 'Draft'),
        ('confirmed', 'Confirmed'),
        ('picked', 'Picked'),
        ('delivered', 'Delivered'),
        ('cancelled', 'Cancelled'),
    ], string="Status", default='draft', tracking=True)

    spx_status = fields.Selection([
        ('secured', 'Secured'),
        ('unsecured', 'Unsecured'),
    ], string="SPX Status",tracking=True,required=True, default='unsecured' )
    security_measurement = fields.Selection([
        ('xray', 'X-Ray'),
        ('ras_cargo', 'RAS-Cargo')
    ], string="Security measurement", tracking=True)
    direct = fields.Boolean(string="Direct",tracking=True)
    handling_agent_id = fields.Many2one('res.partner', string="Ground Handling Agent",
                                        domain=[('gha', '=', True)],tracking=True)
    customer_warehouse_id = fields.Many2one('res.partner', string="Customer Warehouse",
                                            domain=[('warehouse', '=', True)],tracking=True)
    red_folder_required = fields.Boolean(string="C7 Red Folder Required", compute='_compute_red_folder',store=True)
    express = fields.Boolean(string="Express", tracking=True)
    loading_meter = fields.Float(string='Loading meter', tracking=True)
    dangerous = fields.Boolean(string="Dangerous Goods", tracking=True)
    taillift = fields.Boolean(string="Taillift", tracking=True)
    sequence = fields.Char(string="Sequence")

    def name_get(self):
        result = []
        for rec in self:
            name = rec.reference or "New"
            result.append((rec.id, name))
        return result


    _sql_constraints = [
        ('reference_uniq', 'unique(reference)', 'Reference must be unique.'),
    ]

    @api.constrains('total_quantity')
    def _check_total_quantity(self):
        for rec in self:
            if rec.total_quantity and rec.total_quantity < 0:
                raise ValidationError(_("Total quantity cannot be negative."))

    @api.constrains('spx_status', 'vehicle_id')
    def _check_vehicle_security(self):
        for rec in self:
            if rec.spx_status == 'secured' and rec.vehicle_id and not rec.vehicle_id.secured:
                raise ValidationError(_("You must select a secured vehicle when SPX status is 'Secured'."))
            if rec.express and rec.vehicle_id and not rec.vehicle_id.express:
                raise ValidationError(_("You must select an express vehicle."))


    @api.depends('customer_id', 'customer_id.company_ids')
    def _compute_domain_delivery_company_id(self):
        for rec in self:
            if rec.customer_id:
                rec.domain_delivery_company_id = [('id', 'in', rec.customer_id.company_ids.ids)]
            else:
                rec.domain_delivery_company_id = []

    @api.depends('loading_time_from', 'loading_time_to')
    def _compute_loading_time(self):
        for rec in self:
            rec.loading_time = f"{rec.loading_time_from:.2f} - {rec.loading_time_to:.2f}"

    @api.depends('line_ids.quantity', 'line_ids.weight', 'line_ids.volume', 'line_ids.price_unit')
    def _compute_totals(self):
        for rec in self:
            qty = 0
            weight = 0.0
            volume = 0.0
            price = 0.0
            chargeable_weight = 0.0
            for line in rec.line_ids:
                qty += (line.quantity or 0)
                weight += (line.weight or 0.0)
                volume += (line.volume or 0.0)
                chargeable_weight += (line.chargeable_weight or 0.0)
                price += (line.price_unit or 0.0) * (line.quantity or 0)
            rec.total_quantity = qty
            rec.total_weight = weight
            rec.total_volume = volume
            rec.total_chargeable_weight = chargeable_weight
            rec.total_price = price

    @api.depends('spx_status', 'direct', 'security_measurement')
    def _compute_red_folder(self):
        for rec in self:
            if rec.spx_status == 'secured':
                rec.red_folder_required = True
            elif rec.spx_status == 'unsecured' and (rec.direct or rec.security_measurement):
                rec.red_folder_required = True
            else:
                rec.red_folder_required = False

    @api.depends("customer_id")
    def _compute_ref_customer(self):
        # today = datetime.today()
        # year = today.strftime("%Y")
        # month = today.strftime("%m")
        #
        # for rec in self:
        #     if rec.customer_id and rec.customer_id.ref:
        #         count = self.env['shipment.management'].search_count([
        #             ('customer_id', '=', rec.customer_id.id),
        #             ('id', '!=', rec.id)]) + 1
        #         rec.ref_customer = f"{rec.customer_id.ref}-{year}-{month}-{count:04d}"
        #     else:
        #         rec.ref_customer = False
        for rec in self:
            if rec.customer_id and rec.customer_id.order_ref:
                count = self.env['shipment.management'].search_count([
                    ('customer_id', '=', rec.customer_id.id),
                    ('id', '!=', rec.id)]) + 1
                rec.ref_customer = f"{rec.customer_id.order_ref}-{count:04d}"
            else:
                rec.ref_customer = False

    @api.depends('shipment_type')
    def _compute_shipment_type_display(self):
        for rec in self:
            if rec.shipment_type == 'import':
                rec.shipment_type_display = 'A'
            elif rec.shipment_type == 'export':
                rec.shipment_type_display = 'Z'
            else:
                rec.shipment_type_display = ''



    @api.onchange('customer_id')
    def _onchange_customer_id(self):
        if self.customer_id:

            partner_ids = self.customer_id.child_ids | self.customer_id
            gha_partner = partner_ids.filtered(lambda p: p.gha)
            if gha_partner:
                self.handling_agent_id = gha_partner[0]
            else:
                self.handling_agent_id = False

            warehouse_partner = partner_ids.filtered(lambda p: p.warehouse)
            if warehouse_partner:
                self.customer_warehouse_id = warehouse_partner[0]
            else:
                self.customer_warehouse_id = False

            if self.customer_id.company_ids:
                self.delivery_company_id = self.customer_id.company_ids[0]
            else:
                self.delivery_company_id = False


    @api.onchange('delivery_company_id', 'delivery_company_id.zip')
    def _onchange_delivery_company_id(self):
        for rec in self:
            rec.zip_code = False
            if rec.delivery_company_id and rec.delivery_company_id.zip:
                postal = self.env['postal.code'].search(
                    [('name', '=', rec.delivery_company_id.zip)],
                    limit=1
                )
                rec.zip_code = postal.id if postal else False

    @api.onchange('spx_status','express')
    def _onchange_spx_status(self):
        if self.spx_status == 'secured' and self.vehicle_id and not self.vehicle_id.secured:
            self.vehicle_id = False
        if self.express and self.vehicle_id and not self.vehicle_id.express:
            self.vehicle_id = False

    @api.onchange('security_measurement')
    def _onchange_security_measurement(self):
        if self.security_measurement == 'xray' or self.security_measurement == 'ras_cargo' :
            self.direct = True
        else:
            self.direct = False

    def create(self, vals):
        shipment_type = vals.get("shipment_type") or self.env.context.get("default_shipment_type")
        company_id = vals.get('company_id') or self.env.company.id
        if shipment_type == "import":
            seq_code = "shipment.management.import"
        else:
            seq_code = "shipment.management.export"
        if not vals.get("reference") or vals["reference"] == "New":
            vals["reference"] = self.env['ir.sequence'].with_company(company_id).next_by_code(seq_code) or "/"

        shipment = super().create(vals)
        if shipment.customer_id and shipment.delivery_company_id:
            shipment.customer_id.company_ids |= shipment.delivery_company_id
        return shipment

    def write(self, vals):
        res = super().write(vals)
        for rec in self:
            if rec.customer_id and rec.delivery_company_id:
                rec.customer_id.company_ids |= rec.delivery_company_id
        return res


    def action_confirm(self):
        for rec in self:
            if not rec.line_ids:
                raise ValidationError(_("You must add at least one shipment line before confirming."))

            for line in rec.line_ids:
                if line.chargeable_weight <= 0 or line.quantity <= 0:
                    raise ValidationError(_("Chargeable Weight and Quantity must be greater than 0."))

            rec.state = 'confirmed'

    def action_pick(self):
        self.write({'state': 'picked'})

    def action_deliver(self):
        self.write({'state': 'delivered'})

    def action_cancel(self):
        self.write({'state': 'cancelled'})

    def action_reset_to_draft(self):
        self.write({'state': 'draft'})

    def action_open_shipment(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'res_model': 'shipment.management',
            'res_id': self.id,
            'view_mode': 'form',
        }






