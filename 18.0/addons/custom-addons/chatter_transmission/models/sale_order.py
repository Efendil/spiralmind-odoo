from odoo import models, api

class SaleOrder(models.Model):
    _inherit = 'sale.order'

    def create(self, vals):
        order = super().create(vals)
        order._sync_chatter_from_crm()
        return order

    def _sync_chatter_from_crm(self):

        for order in self:
            lead = order.opportunity_id
            if not lead:
                continue

            messages = lead.message_ids.sorted(key=lambda msg: msg.date)

            for message in messages:
                if message.message_type == 'notification':
                    continue
                new_msg = order.message_post(
                    body=message.body,
                    author_id=message.author_id.id if message.author_id else False,
                    message_type=message.message_type,
                    subtype_id=message.subtype_id.id if message.subtype_id else None
                )
                print ('=============',message)
                for attachment in message.attachment_ids:
                    attachment.copy({
                        'res_model': 'sale.order',
                        'res_id': order.id,
                    })
