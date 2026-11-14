# F4 seed: two tenants. The victim inbox has no bot, so a conversation created
# before the attack starts open and one created after starts pending.

require 'json'
require 'securerandom'

PASSWORD = 'LabPassword1!'.freeze

def account_with_admin(name:, email:)
  account = Account.create!(name: name)
  user = User.new(name: name, email: email, password: PASSWORD, password_confirmation: PASSWORD)
  user.skip_confirmation!
  user.save!
  AccountUser.create!(account: account, user: user, role: :administrator)
  [account, user]
end

attacker, attacker_user = account_with_admin(name: 'Attacker Co', email: 'attacker@lab.test')
victim, victim_user = account_with_admin(name: 'Victim Co', email: 'victim@lab.test')

channel = Channel::WebWidget.create!(account: victim, website_url: 'https://victim.example.test')
victim_inbox = Inbox.create!(account: victim, channel: channel, name: 'Victim Support')
victim_contact = victim.contacts.create!(name: 'Victim Customer', email: 'customer@example.test')

File.write('/lab/seed.json', JSON.pretty_generate(
  attacker_account_id: attacker.id,
  attacker_email: attacker_user.email,
  victim_account_id: victim.id,
  victim_email: victim_user.email,
  victim_inbox_id: victim_inbox.id,
  victim_contact_id: victim_contact.id,
  password: PASSWORD,
  witness: 'VICTIM-INBOX-NAME-LEAK'
))

puts "seed complete attacker=#{attacker.id} victim=#{victim.id} victim_inbox=#{victim_inbox.id}"
