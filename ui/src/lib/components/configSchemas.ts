import {
  normalizeChannelSchema,
  normalizeConfigSection,
  type ConfigChannelSchema as ChannelSchema,
  type ConfigSectionDef as SectionDef,
} from "./configSchemaContract";

export type {
  ConfigChannelSchema as ChannelSchema,
  ConfigFieldDef as FieldDef,
  ConfigFieldType as FieldType,
  ConfigSectionDef as SectionDef,
} from "./configSchemaContract";

const rawChannelSchemas = {
  cli: {
    label: 'CLI',
    hasAccounts: false,
    fields: []
  },
  telegram: {
    label: 'Telegram',
    hasAccounts: true,
    fields: [
      { key: 'account_id', label: 'Account ID', type: 'text' },
      { key: 'bot_token', label: 'Bot Token', type: 'password' },
      { key: 'allow_from', label: 'Allow From', type: 'list', default: [], hint: 'Comma-separated @username, username, user IDs, or * for all' },
      { key: 'group_allow_from', label: 'Group Allow From', type: 'list', default: [], advanced: true },
      { key: 'group_policy', label: 'Group Policy', type: 'select', options: ['allowlist', 'open', 'mention_only'], default: 'allowlist', advanced: true },
      { key: 'reply_in_private', label: 'Reply in Private', type: 'toggle', default: true, advanced: true },
      { key: 'require_mention', label: 'Require Mention', type: 'toggle', default: false, advanced: true },
      { key: 'streaming', label: 'Streaming', type: 'toggle', default: false, advanced: true },
      { key: 'status_reactions', label: 'Status Reactions', type: 'toggle', default: true, advanced: true },
      { key: 'binding_commands_enabled', label: 'Binding Commands Enabled', type: 'toggle', default: false, advanced: true },
      { key: 'commands_menu_mode', label: 'Commands Menu Mode', type: 'text', advanced: true },
      { key: 'topic_commands_enabled', label: 'Topic Commands Enabled', type: 'toggle', default: false, advanced: true },
      { key: 'topic_map_command_enabled', label: 'Topic Map Command Enabled', type: 'toggle', default: false, advanced: true },
      { key: 'reaction_emojis.accepted', label: 'Reaction Emoji: Accepted', type: 'text', advanced: true },
      { key: 'reaction_emojis.done', label: 'Reaction Emoji: Done', type: 'text', advanced: true },
      { key: 'reaction_emojis.failed', label: 'Reaction Emoji: Failed', type: 'text', advanced: true },
      { key: 'reaction_emojis.running', label: 'Reaction Emoji: Running', type: 'text', advanced: true },
      { key: 'proxy', label: 'Proxy', type: 'text', hint: 'e.g. socks5://host:port', advanced: true },
      { key: 'interactive.enabled', label: 'Interactive Buttons', type: 'toggle', default: false, advanced: true },
      { key: 'interactive.ttl_secs', label: 'Interactive TTL (secs)', type: 'number', default: 900, advanced: true },
      { key: 'interactive.owner_only', label: 'Interactive Owner Only', type: 'toggle', default: true, advanced: true },
      { key: 'interactive.remove_on_click', label: 'Remove on Click', type: 'toggle', default: true, advanced: true },
    ]
  },
  discord: {
    label: 'Discord',
    hasAccounts: true,
    fields: [
      { key: 'account_id', label: 'Account ID', type: 'text' },
      { key: 'token', label: 'Bot Token', type: 'password' },
      { key: 'guild_id', label: 'Guild ID', type: 'text' },
      { key: 'intents', label: 'Intents', type: 'number' },
      { key: 'allow_bots', label: 'Allow Bots', type: 'toggle', default: false },
      { key: 'allow_from', label: 'Allow From', type: 'list', default: [] },
      { key: 'require_mention', label: 'Require Mention', type: 'toggle', default: false },
    ]
  },
  slack: {
    label: 'Slack',
    hasAccounts: true,
    fields: [
      { key: 'account_id', label: 'Account ID', type: 'text' },
      { key: 'mode', label: 'Mode', type: 'select', options: ['socket', 'http'], default: 'socket' },
      { key: 'bot_token', label: 'Bot Token', type: 'password' },
      { key: 'app_token', label: 'App Token', type: 'password' },
      { key: 'signing_secret', label: 'Signing Secret', type: 'password' },
      { key: 'webhook_path', label: 'Webhook Path', type: 'text', default: '/slack/events' },
      { key: 'channel_id', label: 'Channel ID', type: 'text' },
      { key: 'allow_from', label: 'Allow From', type: 'list', default: [] },
      { key: 'dm_policy', label: 'DM Policy', type: 'select', options: ['pairing', 'allow', 'deny', 'allowlist'], default: 'pairing' },
      { key: 'group_policy', label: 'Group Policy', type: 'select', options: ['mention_only', 'allowlist', 'open'], default: 'mention_only' },
      { key: 'reply_to_mode', label: 'Reply To Mode', type: 'text' },
    ]
  },
  whatsapp: {
    label: 'WhatsApp',
    hasAccounts: true,
    fields: [
      { key: 'account_id', label: 'Account ID', type: 'text' },
      { key: 'access_token', label: 'Access Token', type: 'password' },
      { key: 'phone_number_id', label: 'Phone Number ID', type: 'text' },
      { key: 'verify_token', label: 'Verify Token', type: 'password' },
      { key: 'app_secret', label: 'App Secret', type: 'password' },
      { key: 'allow_from', label: 'Allow From', type: 'list', default: [] },
      { key: 'group_allow_from', label: 'Group Allow From', type: 'list', default: [] },
      { key: 'groups', label: 'Groups', type: 'list', default: [] },
      { key: 'group_policy', label: 'Group Policy', type: 'select', options: ['allowlist', 'open'], default: 'allowlist' },
    ]
  },
  matrix: {
    label: 'Matrix',
    hasAccounts: true,
    fields: [
      { key: 'account_id', label: 'Account ID', type: 'text' },
      { key: 'homeserver', label: 'Homeserver URL', type: 'text' },
      { key: 'access_token', label: 'Access Token', type: 'password' },
      { key: 'room_id', label: 'Room ID', type: 'text' },
      { key: 'user_id', label: 'User ID', type: 'text' },
      { key: 'allow_from', label: 'Allow From', type: 'list', default: [] },
      { key: 'group_allow_from', label: 'Group Allow From', type: 'list', default: [] },
      { key: 'group_policy', label: 'Group Policy', type: 'select', options: ['allowlist', 'open'], default: 'allowlist' },
      { key: 'dm_policy', label: 'DM Policy', type: 'text' },
      { key: 'require_mention', label: 'Require Mention', type: 'toggle', default: false },
    ]
  },
  mattermost: {
    label: 'Mattermost',
    hasAccounts: true,
    fields: [
      { key: 'account_id', label: 'Account ID', type: 'text' },
      { key: 'bot_token', label: 'Bot Token', type: 'password' },
      { key: 'base_url', label: 'Base URL', type: 'text' },
      { key: 'allow_from', label: 'Allow From', type: 'list', default: [] },
      { key: 'group_allow_from', label: 'Group Allow From', type: 'list', default: [] },
      { key: 'dm_policy', label: 'DM Policy', type: 'select', options: ['allowlist', 'allow', 'deny'], default: 'allowlist' },
      { key: 'group_policy', label: 'Group Policy', type: 'select', options: ['allowlist', 'open', 'mention_only'], default: 'allowlist' },
      { key: 'chatmode', label: 'Chat Mode', type: 'select', options: ['oncall', 'always'], default: 'oncall' },
      { key: 'require_mention', label: 'Require Mention', type: 'toggle', default: true },
      { key: 'onchar_prefixes', label: 'On-char Prefixes', type: 'list', default: [], advanced: true },
    ]
  },
  irc: {
    label: 'IRC',
    hasAccounts: true,
    fields: [
      { key: 'account_id', label: 'Account ID', type: 'text' },
      { key: 'host', label: 'Host', type: 'text' },
      { key: 'port', label: 'Port', type: 'number', default: 6697 },
      { key: 'nick', label: 'Nickname', type: 'text' },
      { key: 'username', label: 'Username', type: 'text' },
      { key: 'channels', label: 'Channels', type: 'list', default: [], hint: 'e.g. #general' },
      { key: 'allow_from', label: 'Allow From', type: 'list', default: [] },
      { key: 'server_password', label: 'Server Password', type: 'password' },
      { key: 'nickserv_password', label: 'NickServ Password', type: 'password' },
      { key: 'sasl_password', label: 'SASL Password', type: 'password' },
      { key: 'tls', label: 'TLS', type: 'toggle', default: true },
    ]
  },
  imessage: {
    label: 'iMessage',
    hasAccounts: true,
    fields: [
      { key: 'account_id', label: 'Account ID', type: 'text' },
      { key: 'enabled', label: 'Enabled', type: 'toggle', default: false },
      { key: 'allow_from', label: 'Allow From', type: 'list', default: [] },
      { key: 'group_allow_from', label: 'Group Allow From', type: 'list', default: [] },
      { key: 'group_policy', label: 'Group Policy', type: 'select', options: ['allowlist', 'open'], default: 'allowlist' },
      { key: 'db_path', label: 'DB Path', type: 'text' },
    ]
  },
  email: {
    label: 'Email',
    hasAccounts: true,
    fields: [
      { key: 'account_id', label: 'Account ID', type: 'text' },
      { key: 'imap_host', label: 'IMAP Host', type: 'text' },
      { key: 'imap_port', label: 'IMAP Port', type: 'number', default: 993 },
      { key: 'imap_folder', label: 'IMAP Folder', type: 'text', default: 'INBOX' },
      { key: 'smtp_host', label: 'SMTP Host', type: 'text' },
      { key: 'smtp_port', label: 'SMTP Port', type: 'number', default: 587 },
      { key: 'smtp_tls', label: 'SMTP TLS', type: 'toggle', default: true },
      { key: 'username', label: 'Username', type: 'text' },
      { key: 'password', label: 'Password', type: 'password' },
      { key: 'from_address', label: 'From Address', type: 'text' },
      { key: 'poll_interval_secs', label: 'Poll Interval (secs)', type: 'number', default: 60 },
      { key: 'consent_granted', label: 'Consent Granted', type: 'toggle', default: false },
      { key: 'allow_from', label: 'Allow From', type: 'list', default: [] },
    ]
  },
  lark: {
    label: 'Lark/Feishu',
    hasAccounts: true,
    fields: [
      { key: 'account_id', label: 'Account ID', type: 'text' },
      { key: 'app_id', label: 'App ID', type: 'text' },
      { key: 'app_secret', label: 'App Secret', type: 'password' },
      { key: 'encrypt_key', label: 'Encrypt Key', type: 'password' },
      { key: 'verification_token', label: 'Verification Token', type: 'password' },
      { key: 'port', label: 'Port', type: 'number' },
      { key: 'use_feishu', label: 'Use Feishu', type: 'toggle', default: false },
      { key: 'allow_from', label: 'Allow From', type: 'list', default: [] },
      { key: 'receive_mode', label: 'Receive Mode', type: 'select', options: ['websocket', 'webhook'], default: 'websocket' },
    ]
  },
  dingtalk: {
    label: 'DingTalk',
    hasAccounts: true,
    fields: [
      { key: 'account_id', label: 'Account ID', type: 'text' },
      { key: 'client_id', label: 'Client ID', type: 'text' },
      { key: 'client_secret', label: 'Client Secret', type: 'password' },
      { key: 'allow_from', label: 'Allow From', type: 'list', default: [] },
      { key: 'ai_card_streaming_key', label: 'AI Card Streaming Key', type: 'text', advanced: true },
      { key: 'ai_card_template_id', label: 'AI Card Template ID', type: 'text', advanced: true },
    ]
  },
  wechat: {
    label: 'WeChat',
    hasAccounts: true,
    fields: [
      { key: 'account_id', label: 'Account ID', type: 'text' },
      { key: 'callback_token', label: 'Callback Token', type: 'password' },
      { key: 'encoding_aes_key', label: 'Encoding AES Key', type: 'password' },
      { key: 'app_id', label: 'App ID', type: 'text' },
      { key: 'app_secret', label: 'App Secret', type: 'password' },
      { key: 'allow_from', label: 'Allow From', type: 'list', default: [] },
    ]
  },
  wecom: {
    label: 'WeCom',
    hasAccounts: true,
    fields: [
      { key: 'account_id', label: 'Account ID', type: 'text' },
      { key: 'webhook_url', label: 'Webhook URL', type: 'text' },
      { key: 'callback_token', label: 'Callback Token', type: 'password' },
      { key: 'encoding_aes_key', label: 'Encoding AES Key', type: 'password' },
      { key: 'corp_id', label: 'Corp ID', type: 'text' },
      { key: 'allow_from', label: 'Allow From', type: 'list', default: [] },
    ]
  },
  signal: {
    label: 'Signal',
    hasAccounts: true,
    fields: [
      { key: 'account_id', label: 'Account ID', type: 'text' },
      { key: 'http_url', label: 'HTTP URL', type: 'text' },
      { key: 'account', label: 'Account', type: 'text' },
      { key: 'allow_from', label: 'Allow From', type: 'list', default: [] },
      { key: 'group_allow_from', label: 'Group Allow From', type: 'list', default: [] },
      { key: 'group_policy', label: 'Group Policy', type: 'select', options: ['allowlist', 'open'], default: 'allowlist' },
      { key: 'ignore_attachments', label: 'Ignore Attachments', type: 'toggle', default: false },
      { key: 'ignore_stories', label: 'Ignore Stories', type: 'toggle', default: false },
    ]
  },
  line: {
    label: 'LINE',
    hasAccounts: true,
    fields: [
      { key: 'account_id', label: 'Account ID', type: 'text' },
      { key: 'access_token', label: 'Access Token', type: 'password' },
      { key: 'channel_secret', label: 'Channel Secret', type: 'password' },
      { key: 'port', label: 'Port', type: 'number' },
      { key: 'allow_from', label: 'Allow From', type: 'list', default: [] },
    ]
  },
  qq: {
    label: 'QQ',
    hasAccounts: true,
    fields: [
      { key: 'account_id', label: 'Account ID', type: 'text' },
      { key: 'app_id', label: 'App ID', type: 'text' },
      { key: 'app_secret', label: 'App Secret', type: 'password' },
      { key: 'bot_token', label: 'Bot Token', type: 'password' },
      { key: 'sandbox', label: 'Sandbox', type: 'toggle', default: false },
      { key: 'receive_mode', label: 'Receive Mode', type: 'select', options: ['websocket', 'webhook'], default: 'webhook' },
      { key: 'group_policy', label: 'Group Policy', type: 'select', options: ['allow', 'allowlist'], default: 'allow' },
      { key: 'allowed_groups', label: 'Allowed Groups', type: 'list', default: [] },
      { key: 'allow_from', label: 'Allow From', type: 'list', default: [] },
    ]
  },
  onebot: {
    label: 'OneBot',
    hasAccounts: true,
    fields: [
      { key: 'account_id', label: 'Account ID', type: 'text' },
      { key: 'url', label: 'WebSocket URL', type: 'text', default: 'ws://localhost:6700' },
      { key: 'access_token', label: 'Access Token', type: 'password' },
      { key: 'group_trigger_prefix', label: 'Group Trigger Prefix', type: 'text' },
      { key: 'allow_from', label: 'Allow From', type: 'list', default: [] },
    ]
  },
  maixcam: {
    label: 'MaixCam',
    hasAccounts: true,
    fields: [
      { key: 'account_id', label: 'Account ID', type: 'text' },
      { key: 'port', label: 'Port', type: 'number', default: 7777 },
      { key: 'host', label: 'Host', type: 'text', default: '0.0.0.0' },
      { key: 'allow_from', label: 'Allow From', type: 'list', default: [] },
      { key: 'name', label: 'Name', type: 'text', default: 'maixcam' },
    ]
  },
  web: {
    label: 'Web',
    hasAccounts: true,
    fields: [
      { key: 'account_id', label: 'Account ID', type: 'text' },
      { key: 'transport', label: 'Transport', type: 'select', options: ['local', 'relay'], default: 'local' },
      { key: 'max_connections', label: 'Max Connections', type: 'number', default: 10 },
      { key: 'listen', label: 'Listen', type: 'text', default: '0.0.0.0' },
      { key: 'port', label: 'Port', type: 'number', default: 8787 },
      { key: 'path', label: 'Path', type: 'text', default: '/ws' },
      { key: 'max_handshake_size', label: 'Max Handshake Size (bytes)', type: 'number', default: 262144 },
      { key: 'auth_token', label: 'Auth Token', type: 'password' },
      { key: 'message_auth_mode', label: 'Auth Mode', type: 'select', options: ['pairing', 'token'], default: 'pairing' },
      { key: 'allowed_origins', label: 'Allowed Origins', type: 'list', default: [] },
      { key: 'relay_url', label: 'Relay URL', type: 'text', hint: 'Must start with wss://' },
      { key: 'relay_agent_id', label: 'Relay Agent ID', type: 'text', default: 'default' },
      { key: 'relay_token', label: 'Relay Token', type: 'password' },
      { key: 'relay_e2e_required', label: 'Relay E2E Required', type: 'toggle', default: false },
      { key: 'relay_pairing_code_ttl_secs', label: 'Relay Pairing Code TTL (secs)', type: 'number', default: 300 },
      { key: 'relay_token_ttl_secs', label: 'Relay Token TTL (secs)', type: 'number', default: 3600 },
      { key: 'relay_ui_token_ttl_secs', label: 'Relay UI Token TTL (secs)', type: 'number', default: 3600 },
    ]
  },
  external: {
    label: 'External',
    hasAccounts: true,
    fields: [
      { key: 'account_id', label: 'Account ID', type: 'text' },
      { key: 'runtime_name', label: 'Runtime Name', type: 'text' },
      { key: 'plugin_config_json', label: 'Plugin Config JSON', type: 'text', hint: 'Raw JSON string for external plugin' },
      { key: 'config.allow_from', label: 'Allow From', type: 'list', default: [] },
      { key: 'config.bridge_url', label: 'Bridge URL', type: 'text' },
      { key: 'transport.command', label: 'Transport Command', type: 'text' },
      { key: 'transport.args', label: 'Transport Args', type: 'list', default: [] },
      {
        key: 'transport.env',
        label: 'Transport Environment',
        type: 'json',
        default: {},
        editorKind: 'key-value',
        addLabel: 'Add Environment Variable',
        emptyLabel: 'No environment variables configured.',
        itemFields: [
          { key: 'key', path: 'channels.external.accounts.<account>.transport.env[*].key', label: 'Variable Name', type: 'text' },
          { key: 'value', path: 'channels.external.accounts.<account>.transport.env[*].value', label: 'Variable Value', type: 'text' },
        ],
      },
      { key: 'transport.timeout_ms', label: 'Transport Timeout (ms)', type: 'number', default: 30000 },
    ]
  },
  max: {
    label: 'MAX',
    hasAccounts: true,
    fields: [
      { key: 'account_id', label: 'Account ID', type: 'text' },
      { key: 'mode', label: 'Mode', type: 'text' },
      { key: 'bot_token', label: 'Bot Token', type: 'password' },
      { key: 'webhook_url', label: 'Webhook URL', type: 'text' },
      { key: 'webhook_secret', label: 'Webhook Secret', type: 'password' },
      { key: 'allow_from', label: 'Allow From', type: 'list', default: [] },
      { key: 'group_allow_from', label: 'Group Allow From', type: 'list', default: [] },
      { key: 'group_policy', label: 'Group Policy', type: 'select', options: ['allowlist', 'open', 'mention_only'], default: 'allowlist' },
      { key: 'require_mention', label: 'Require Mention', type: 'toggle', default: false },
      { key: 'proxy', label: 'Proxy', type: 'text' },
      { key: 'streaming', label: 'Streaming', type: 'toggle', default: false },
      { key: 'interactive.enabled', label: 'Interactive Enabled', type: 'toggle', default: false, advanced: true },
      { key: 'interactive.ttl_secs', label: 'Interactive TTL (secs)', type: 'number', default: 900, advanced: true },
      { key: 'interactive.owner_only', label: 'Interactive Owner Only', type: 'toggle', default: true, advanced: true },
    ]
  },
  teams: {
    label: 'Teams',
    hasAccounts: true,
    fields: [
      { key: 'account_id', label: 'Account ID', type: 'text' },
      { key: 'bot_id', label: 'Bot ID', type: 'text' },
      { key: 'client_id', label: 'Client ID', type: 'text' },
      { key: 'client_secret', label: 'Client Secret', type: 'password' },
      { key: 'notification_channel_id', label: 'Notification Channel ID', type: 'text' },
      { key: 'tenant_id', label: 'Tenant ID', type: 'text' },
      { key: 'webhook_secret', label: 'Webhook Secret', type: 'password' },
    ]
  },
  nostr: {
    label: 'Nostr',
    hasAccounts: false,
    fields: [
      { key: 'private_key', label: 'Private Key', type: 'password', hint: 'enc2:-encrypted' },
      { key: 'owner_pubkey', label: 'Owner Pubkey', type: 'text', hint: '64-char lowercase hex' },
      { key: 'bot_pubkey', label: 'Bot Pubkey', type: 'text' },
      { key: 'relays', label: 'Relays', type: 'list', default: [] },
      { key: 'dm_relays', label: 'DM Relays', type: 'list', default: [] },
      { key: 'dm_allowed_pubkeys', label: 'DM Allowed Pubkeys', type: 'list', default: [] },
      { key: 'display_name', label: 'Display Name', type: 'text', default: 'NullClaw' },
      { key: 'display_pic', label: 'Display Picture URL', type: 'text' },
      { key: 'about', label: 'About', type: 'text', default: 'AI assistant' },
      { key: 'nip05', label: 'NIP-05', type: 'text' },
      { key: 'bunker_uri', label: 'Bunker URI', type: 'text' },
      { key: 'lnurl', label: 'LNURL', type: 'text' },
      { key: 'nak_path', label: 'Nak Path', type: 'text' },
    ]
  },
  webhook: {
    label: 'Webhook',
    hasAccounts: false,
    fields: [
      { key: 'port', label: 'Port', type: 'number', default: 9000 },
      { key: 'secret', label: 'Secret', type: 'password' },
    ]
  }
} satisfies Record<string, ChannelSchema>;

export const channelSchemas: Record<string, ChannelSchema> = Object.fromEntries(
  Object.entries(rawChannelSchemas).map(([key, schema]) => [key, normalizeChannelSchema(schema, key)]),
) as Record<string, ChannelSchema>;

const memoryProfileOptions = [
  "hybrid_keyword",
  "local_keyword",
  "markdown_only",
  "postgres_keyword",
  "local_hybrid",
  "postgres_hybrid",
  "minimal_none",
  "custom",
];

const memoryStoreKindOptions = ["auto", "sqlite_ann", "sqlite_shared", "pgvector", "qdrant"];
const memorySyncModeOptions = ["best_effort", "durable_outbox"];
const memoryRolloutModeOptions = ["off", "on", "shadow", "canary"];
const memoryFallbackPolicyOptions = ["degrade", "fail_fast"];

const rawStaticSections: SectionDef[] = [
  {
    key: 'models',
    label: 'Models & Providers',
    group: 'providers',
    fields: [
      { key: 'default_temperature', label: 'Default Temperature', type: 'number', default: 0.7, min: 0, max: 2, step: 0.1 },
      { key: 'default_provider', label: 'Default Provider', type: 'text', hint: 'e.g. openrouter' },
      { key: 'default_model', label: 'Default Model ID', type: 'text', hint: 'Provider-native model name' },
      { key: 'reasoning_effort', label: 'Reasoning Effort', type: 'select', options: ['low', 'medium', 'high', 'xhigh'], default: 'medium' },
      { key: 'agents.defaults.model.primary', label: 'Default Model', type: 'text', hint: 'e.g. openrouter/anthropic/claude-sonnet-4.6' },
      { key: 'agents.defaults.heartbeat.enabled', label: 'Default Heartbeat Enabled', type: 'toggle', default: false },
      { key: 'agents.defaults.heartbeat.every', label: 'Default Heartbeat Every', type: 'text' },
      { key: 'agents.defaults.heartbeat.interval_minutes', label: 'Default Heartbeat Interval (mins)', type: 'number', default: 60, min: 1 },
      { key: 'agents.list', label: 'Agent List', type: 'list', default: [], hint: 'One agent ID per line' },
      {
        key: 'reliability.model_fallbacks',
        label: 'Model Fallbacks',
        type: 'json',
        default: [],
        hint: 'Define fallback chains for specific primary models.',
        editorKind: 'object-list',
        addLabel: 'Add Fallback Chain',
        emptyLabel: 'No model fallback chains configured.',
        itemFields: [
          { key: 'model', path: 'reliability.model_fallbacks[*].model', label: 'Primary Model', type: 'text' },
          { key: 'fallbacks', path: 'reliability.model_fallbacks[*].fallbacks', label: 'Fallback Models', type: 'list', default: [], hint: 'One fallback model per line' },
        ],
      },
      { key: 'reliability.fallback_providers', label: 'Fallback Providers', type: 'list', default: [], hint: 'One provider per line' },
      { key: 'models.providers.openrouter.api_key', label: 'OpenRouter API Key', type: 'password' },
      { key: 'models.providers.azure.api_key', label: 'Azure API Key', type: 'password' },
      { key: 'models.providers.azure.base_url', label: 'Azure Base URL', type: 'text' },
      { key: 'models.providers.vertex.base_url', label: 'Vertex Base URL', type: 'text' },
      { key: 'models.providers.vertex.api_key.type', label: 'Vertex API Key Type', type: 'text' },
      { key: 'models.providers.vertex.api_key.project_id', label: 'Vertex Project ID', type: 'text' },
      { key: 'models.providers.vertex.api_key.client_email', label: 'Vertex Client Email', type: 'text' },
      { key: 'models.providers.vertex.api_key.private_key', label: 'Vertex Private Key', type: 'password' },
    ]
  },
  {
    key: 'agent',
    label: 'Agent',
    group: 'general',
    fields: [
      { key: 'agent.max_tool_iterations', label: 'Max Tool Iterations', type: 'number', default: 25 },
      { key: 'agent.max_history_messages', label: 'Max History Messages', type: 'number', default: 50 },
      { key: 'agent.session_idle_timeout_secs', label: 'Session Idle Timeout (secs)', type: 'number', default: 1800 },
      { key: 'agent.parallel_tools', label: 'Parallel Tools', type: 'toggle', default: false },
      { key: 'agent.compact_context', label: 'Compact Context', type: 'toggle', default: false },
      { key: 'agent.message_timeout_secs', label: 'Message Timeout (secs)', type: 'number', default: 300 },
      { key: 'agent.timezone', label: 'Timezone', type: 'text', default: 'UTC', hint: 'UTC or fixed offsets like UTC+08:00 / UTC-05:00' },
      { key: 'agent.auto_disable_vision_on_error', label: 'Auto Disable Vision On Error', type: 'toggle', default: false },
      { key: 'agent.status_show_emojis', label: 'Status Show Emojis', type: 'toggle', default: true },
      { key: 'agent.token_limit', label: 'Token Limit', type: 'number', min: 1 },
      { key: 'agent.tool_dispatcher', label: 'Tool Dispatcher', type: 'text' },
      { key: 'agent.compaction_keep_recent', label: 'Compaction Keep Recent', type: 'number', min: 0 },
      { key: 'agent.compaction_max_source_chars', label: 'Compaction Max Source Chars', type: 'number', min: 0 },
      { key: 'agent.compaction_max_summary_chars', label: 'Compaction Max Summary Chars', type: 'number', min: 0 },
      {
        key: 'agent.tool_filter_groups',
        label: 'Tool Filter Groups',
        type: 'json',
        default: [],
        hint: 'Group MCP tool patterns by mode and optional activation keywords.',
        editorKind: 'object-list',
        addLabel: 'Add Filter Group',
        emptyLabel: 'No tool filter groups configured.',
        itemFields: [
          { key: 'mode', path: 'agent.tool_filter_groups[*].mode', label: 'Mode', type: 'select', options: ['always', 'dynamic'], default: 'dynamic' },
          { key: 'tools', path: 'agent.tool_filter_groups[*].tools', label: 'Tool Patterns', type: 'list', default: [], hint: 'One glob pattern per line' },
          { key: 'keywords', path: 'agent.tool_filter_groups[*].keywords', label: 'Keywords', type: 'list', default: [], hint: 'Used only in dynamic mode' },
        ],
      },
      { key: 'agent.vision_disabled_models', label: 'Vision-disabled Models', type: 'list', default: [] },
    ]
  },
  {
    key: 'autonomy',
    label: 'Autonomy',
    group: 'behavior',
    fields: [
      { key: 'autonomy.level', label: 'Level', type: 'select', options: ['supervised', 'autonomous', 'off'], default: 'supervised' },
      { key: 'autonomy.workspace_only', label: 'Workspace Only', type: 'toggle', default: true },
      { key: 'autonomy.max_actions_per_hour', label: 'Max Actions / Hour', type: 'number', default: 20 },
      { key: 'autonomy.require_approval_for_medium_risk', label: 'Require Approval (Medium Risk)', type: 'toggle', default: true },
      { key: 'autonomy.block_high_risk_commands', label: 'Block High Risk Commands', type: 'toggle', default: true },
      { key: 'autonomy.allow_raw_url_chars', label: 'Allow Raw URL Chars', type: 'toggle', default: false },
      { key: 'autonomy.allowed_commands', label: 'Allowed Commands', type: 'list', default: [] },
      { key: 'autonomy.allowed_paths', label: 'Allowed Paths', type: 'list', default: [] },
    ]
  },
  {
    key: 'diagnostics',
    label: 'Diagnostics',
    group: 'advanced',
    fields: [
      { key: 'diagnostics.log_tool_calls', label: 'Log Tool Calls', type: 'toggle', default: true },
      { key: 'diagnostics.log_message_receipts', label: 'Log Message Receipts', type: 'toggle', default: true },
      { key: 'diagnostics.log_message_payloads', label: 'Log Message Payloads', type: 'toggle', default: false },
      { key: 'diagnostics.log_llm_io', label: 'Log LLM I/O', type: 'toggle', default: false },
      { key: 'diagnostics.backend', label: 'Diagnostics Backend', type: 'text' },
      { key: 'diagnostics.api_error_max_chars', label: 'API Error Max Chars', type: 'number', min: 0 },
      { key: 'diagnostics.otel_endpoint', path: 'diagnostics.otel.endpoint', label: 'OTEL Endpoint', type: 'text' },
      { key: 'diagnostics.otel_service_name', path: 'diagnostics.otel.service_name', label: 'OTEL Service Name', type: 'text' },
      {
        key: 'diagnostics.otel_headers',
        path: 'diagnostics.otel.headers',
        label: 'OTEL Headers',
        type: 'json',
        default: {},
        hint: 'Add OTEL header key/value pairs.',
        editorKind: 'key-value',
        addLabel: 'Add OTEL Header',
        emptyLabel: 'No OTEL headers configured.',
        itemFields: [
          { key: 'key', path: 'diagnostics.otel_headers[*].key', label: 'Header Name', type: 'text' },
          { key: 'value', path: 'diagnostics.otel_headers[*].value', label: 'Header Value', type: 'text' },
        ],
      },
      { key: 'diagnostics.token_usage_ledger_enabled', label: 'Token Usage Ledger Enabled', type: 'toggle', default: false },
      { key: 'diagnostics.token_usage_ledger_max_bytes', label: 'Token Usage Ledger Max Bytes', type: 'number', min: 0 },
      { key: 'diagnostics.token_usage_ledger_max_lines', label: 'Token Usage Ledger Max Lines', type: 'number', min: 0 },
      { key: 'diagnostics.token_usage_ledger_window_hours', label: 'Token Usage Ledger Window (hours)', type: 'number', min: 0 },
    ]
  },
  {
    key: 'browser',
    label: 'Browser',
    group: 'behavior',
    fields: [
      { key: 'browser.enabled', label: 'Enabled', type: 'toggle', default: false },
      { key: 'browser.backend', label: 'Backend', type: 'text' },
      { key: 'browser.session_name', label: 'Session Name', type: 'text' },
      { key: 'browser.allowed_domains', label: 'Allowed Domains', type: 'list', default: [] },
      { key: 'browser.native_chrome_path', label: 'Native Chrome Path', type: 'text' },
      { key: 'browser.native_headless', label: 'Native Headless', type: 'toggle', default: true },
      { key: 'browser.native_webdriver_url', label: 'Native WebDriver URL', type: 'text' },
      { key: 'browser.computer_use.endpoint', label: 'Computer Use Endpoint', type: 'text' },
      { key: 'browser.computer_use.api_key', label: 'Computer Use API Key', type: 'password' },
      { key: 'browser.computer_use.allow_remote_endpoint', label: 'Allow Remote Endpoint', type: 'toggle', default: false },
      { key: 'browser.computer_use.max_coordinate_x', label: 'Max Coordinate X', type: 'number', min: 0 },
      { key: 'browser.computer_use.max_coordinate_y', label: 'Max Coordinate Y', type: 'number', min: 0 },
      { key: 'browser.computer_use.timeout_ms', label: 'Computer Use Timeout (ms)', type: 'number', min: 1 },
    ]
  },
  {
    key: 'gateway',
    label: 'Gateway',
    group: 'general',
    fields: [
      { key: 'gateway.host', label: 'Gateway Host', type: 'text', default: '127.0.0.1' },
      { key: 'gateway.port', label: 'Gateway Port', type: 'number', default: 3000, min: 1, max: 65535 },
      { key: 'gateway.require_pairing', label: 'Require Pairing', type: 'toggle', default: true },
      { key: 'gateway.allow_public_bind', label: 'Allow Public Bind', type: 'toggle', default: false },
      { key: 'gateway.pair_rate_limit_per_minute', label: 'Pair Rate Limit / Min', type: 'number', default: 10, min: 1 },
      { key: 'gateway.webhook_rate_limit_per_minute', label: 'Webhook Rate Limit / Min', type: 'number', default: 60, min: 1 },
      { key: 'gateway.idempotency_ttl_secs', label: 'Idempotency TTL (secs)', type: 'number', default: 300, min: 0 },
      { key: 'gateway.paired_tokens', label: 'Paired Tokens', type: 'list', default: [] },
    ]
  },
  {
    key: 'reliability',
    label: 'Reliability',
    group: 'reliability',
    fields: [
      { key: 'reliability.provider_retries', label: 'Provider Retries', type: 'number', default: 2, min: 0 },
      { key: 'reliability.provider_backoff_ms', label: 'Provider Backoff (ms)', type: 'number', default: 500, min: 0 },
      { key: 'reliability.channel_initial_backoff_secs', label: 'Channel Initial Backoff (secs)', type: 'number', default: 2, min: 0 },
      { key: 'reliability.channel_max_backoff_secs', label: 'Channel Max Backoff (secs)', type: 'number', default: 60, min: 0 },
      { key: 'reliability.scheduler_poll_secs', label: 'Scheduler Poll (secs)', type: 'number', default: 15, min: 1 },
      { key: 'reliability.scheduler_retries', label: 'Scheduler Retries', type: 'number', default: 2, min: 0 },
      { key: 'reliability.api_keys', label: 'API Keys', type: 'list', default: [] },
    ]
  },
  {
    key: 'security',
    label: 'Security',
    group: 'reliability',
    fields: [
      { key: 'security.sandbox.enabled', label: 'Sandbox Enabled', type: 'toggle', default: true },
      { key: 'security.sandbox.backend', label: 'Sandbox Backend', type: 'select', options: ['auto', 'landlock', 'firejail', 'bubblewrap', 'docker', 'none'], default: 'auto' },
      { key: 'security.sandbox.firejail_args', label: 'Firejail Args', type: 'list', default: [] },
      { key: 'security.audit.enabled', label: 'Audit Enabled', type: 'toggle', default: true },
      { key: 'security.audit.retention_days', label: 'Audit Retention (days)', type: 'number', default: 90, min: 1 },
      { key: 'security.audit.log_path', label: 'Audit Log Path', type: 'text' },
      { key: 'security.audit.log_file', label: 'Audit Log File', type: 'text' },
      { key: 'security.audit.max_size_mb', label: 'Audit Max Size (MB)', type: 'number', min: 1 },
      { key: 'security.audit.sign_events', label: 'Audit Sign Events', type: 'toggle', default: false },
      { key: 'security.resources.max_memory_mb', label: 'Max Memory (MB)', type: 'number', default: 512, min: 1 },
      { key: 'security.resources.max_cpu_percent', label: 'Max CPU (%)', type: 'number', default: 80, min: 1, max: 100 },
      { key: 'security.resources.max_disk_mb', label: 'Max Disk (MB)', type: 'number', default: 1024, min: 1 },
      { key: 'security.resources.max_subprocesses', label: 'Max Subprocesses', type: 'number', default: 10, min: 1 },
      { key: 'security.resources.max_cpu_time_seconds', label: 'Max CPU Time (secs)', type: 'number', min: 1 },
      { key: 'security.resources.memory_monitoring', label: 'Memory Monitoring', type: 'toggle', default: true },
    ]
  },
  {
    key: 'runtime',
    label: 'Runtime',
    group: 'general',
    fields: [
      { key: 'runtime.kind', label: 'Runtime Kind', type: 'select', options: ['native', 'docker'], default: 'native' },
      { key: 'runtime.docker.image', label: 'Docker Image', type: 'text', default: 'alpine:3.20' },
      { key: 'runtime.docker.network', label: 'Docker Network', type: 'text', default: 'none' },
      { key: 'runtime.docker.cpu_limit', label: 'Docker CPU Limit', type: 'number', step: 0.1, min: 0 },
      { key: 'runtime.docker.memory_limit_mb', label: 'Docker Memory Limit (MB)', type: 'number', default: 512, min: 0 },
      { key: 'runtime.docker.read_only_rootfs', label: 'Read-only RootFS', type: 'toggle', default: true },
      { key: 'runtime.docker.mount_workspace', label: 'Mount Workspace', type: 'toggle', default: true },
    ]
  },
  {
    key: 'tools',
    label: 'Tools',
    group: 'behavior',
    fields: [
      { key: 'tools.shell_timeout_secs', label: 'Shell Timeout (secs)', type: 'number', default: 60, min: 1 },
      { key: 'tools.shell_max_output_bytes', label: 'Shell Max Output (bytes)', type: 'number', default: 1048576, min: 1024 },
      { key: 'tools.max_file_size_bytes', label: 'Max File Size (bytes)', type: 'number', default: 10485760, min: 1024 },
      { key: 'tools.web_fetch_max_chars', label: 'Web Fetch Max Chars', type: 'number', default: 100000, min: 1000 },
      { key: 'tools.path_env_vars', label: 'Path Env Vars', type: 'list', default: [], hint: 'One env var per line' },
      { key: 'tools.media.audio.enabled', label: 'Audio Tool Enabled', type: 'toggle', default: false },
      { key: 'tools.media.audio.language', label: 'Audio Language', type: 'text' },
      { key: 'tools.media.audio.models', label: 'Audio Models', type: 'list', default: [] },
    ]
  },
  {
    key: 'http_request',
    label: 'HTTP Request',
    group: 'behavior',
    fields: [
      { key: 'http_request.enabled', label: 'Enabled', type: 'toggle', default: false },
      { key: 'http_request.max_response_size', label: 'Max Response Size (bytes)', type: 'number', default: 1000000, min: 1024 },
      { key: 'http_request.timeout_secs', label: 'Timeout (secs)', type: 'number', default: 30, min: 1 },
      { key: 'http_request.allowed_domains', label: 'Allowed Domains', type: 'list', default: [], hint: 'One domain per line' },
      { key: 'http_request.proxy', label: 'Proxy URL', type: 'text', hint: 'Optional, e.g. http://127.0.0.1:7890' },
      { key: 'http_request.search_provider', label: 'Search Provider', type: 'select', options: ['auto', 'jina', 'duckduckgo'], default: 'auto' },
      { key: 'http_request.search_base_url', label: 'Search Base URL', type: 'text' },
      { key: 'http_request.search_fallback_providers', label: 'Search Fallback Providers', type: 'list', default: [] },
    ]
  },
  {
    key: 'session',
    label: 'Session',
    group: 'behavior',
    fields: [
      { key: 'session.dm_scope', label: 'DM Scope', type: 'select', options: ['main', 'per_peer', 'per_channel_peer', 'per_account_channel_peer'], default: 'per_channel_peer' },
      { key: 'session.idle_minutes', label: 'Idle Minutes', type: 'number', default: 60, min: 1 },
      { key: 'session.typing_interval_secs', label: 'Typing Interval (secs)', type: 'number', default: 5, min: 1 },
      { key: 'session.max_concurrent_tasks', label: 'Max Concurrent Tasks', type: 'number', default: 4, min: 1 },
      { key: 'session.auto_provision_direct_agents', label: 'Auto Provision Direct Agents', type: 'toggle', default: false },
      {
        key: 'session.identity_links',
        label: 'Identity Links',
        type: 'json',
        default: [],
        hint: 'Map canonical identities to one or more peer identifiers.',
        editorKind: 'object-list',
        addLabel: 'Add Identity Link',
        emptyLabel: 'No identity links configured.',
        itemFields: [
          { key: 'canonical', path: 'session.identity_links[*].canonical', label: 'Canonical Identity', type: 'text' },
          { key: 'peers', path: 'session.identity_links[*].peers', label: 'Peers', type: 'list', default: [], hint: 'One peer ID per line' },
        ],
      },
      { key: 'session.claim_secret', label: 'Claim Secret', type: 'password' },
      { key: 'session.claim_admin_secret', label: 'Claim Admin Secret', type: 'password' },
      { key: 'session.claim_max_attempts', label: 'Claim Max Attempts', type: 'number', default: 5, min: 1 },
      { key: 'session.claim_lockout_secs', label: 'Claim Lockout (secs)', type: 'number', default: 300, min: 1 },
    ]
  },
  {
    key: 'cost',
    label: 'Cost',
    group: 'behavior',
    fields: [
      { key: 'cost.enabled', label: 'Enabled', type: 'toggle', default: false },
      { key: 'cost.allow_override', label: 'Allow Override', type: 'toggle', default: false },
      { key: 'cost.daily_limit_usd', label: 'Daily Limit (USD)', type: 'number', min: 0, step: 0.01 },
      { key: 'cost.monthly_limit_usd', label: 'Monthly Limit (USD)', type: 'number', min: 0, step: 0.01 },
      { key: 'cost.warn_at_percent', label: 'Warn At Percent', type: 'number', min: 1, max: 100 },
    ]
  },
  {
    key: 'cron',
    label: 'Cron',
    group: 'behavior',
    fields: [
      { key: 'cron.enabled', label: 'Enabled', type: 'toggle', default: false },
      { key: 'cron.interval_minutes', label: 'Interval (mins)', type: 'number', min: 1 },
      { key: 'cron.max_run_history', label: 'Max Run History', type: 'number', min: 0 },
    ]
  },
  {
    key: 'scheduler',
    label: 'Scheduler',
    group: 'behavior',
    fields: [
      { key: 'scheduler.enabled', label: 'Enabled', type: 'toggle', default: false },
      { key: 'scheduler.max_tasks', label: 'Max Tasks', type: 'number', min: 1 },
      { key: 'scheduler.max_concurrent', label: 'Max Concurrent', type: 'number', min: 1 },
      { key: 'scheduler.agent_timeout_secs', label: 'Agent Timeout (secs)', type: 'number', min: 1 },
    ]
  },
  {
    key: 'identity',
    label: 'Identity',
    group: 'general',
    fields: [
      { key: 'identity.format', label: 'Format', type: 'text' },
      { key: 'identity.aieos_inline', label: 'AIEOS Inline', type: 'text' },
      { key: 'identity.aieos_path', label: 'AIEOS Path', type: 'text' },
    ]
  },
  {
    key: 'heartbeat',
    label: 'Heartbeat',
    group: 'general',
    fields: [
      { key: 'heartbeat.enabled', label: 'Enabled', type: 'toggle', default: false },
      { key: 'heartbeat.interval_minutes', label: 'Interval (mins)', type: 'number', min: 1 },
    ]
  },
  {
    key: 'peripherals',
    label: 'Peripherals',
    group: 'peripherals',
    fields: [
      { key: 'peripherals.enabled', label: 'Enabled', type: 'toggle', default: false },
      { key: 'peripherals.datasheet_dir', label: 'Datasheet Directory', type: 'text' },
      {
        key: 'peripherals.boards',
        label: 'Boards',
        type: 'json',
        default: [],
        hint: 'Declare peripheral boards for serial or probe-based integrations.',
        editorKind: 'object-list',
        addLabel: 'Add Board',
        emptyLabel: 'No peripheral boards configured.',
        itemFields: [
          { key: 'board', path: 'peripherals.boards[*].board', label: 'Board', type: 'text' },
          { key: 'transport', path: 'peripherals.boards[*].transport', label: 'Transport', type: 'text', default: 'serial' },
          { key: 'path', path: 'peripherals.boards[*].path', label: 'Path', type: 'text' },
          { key: 'baud', path: 'peripherals.boards[*].baud', label: 'Baud', type: 'number', default: 115200, min: 1 },
        ],
      },
    ]
  },
  {
    key: 'a2a',
    label: 'A2A',
    group: 'advanced',
    fields: [
      { key: 'a2a.enabled', label: 'Enabled', type: 'toggle', default: false },
      { key: 'a2a.name', label: 'Name', type: 'text' },
      { key: 'a2a.description', label: 'Description', type: 'text' },
      { key: 'a2a.url', label: 'URL', type: 'text' },
      { key: 'a2a.version', label: 'Version', type: 'text' },
    ]
  },
  {
    key: 'composio',
    label: 'Composio',
    group: 'behavior',
    fields: [
      { key: 'composio.enabled', label: 'Enabled', type: 'toggle', default: false },
      { key: 'composio.api_key', label: 'API Key', type: 'password' },
      { key: 'composio.entity_id', label: 'Entity ID', type: 'text' },
    ]
  },
  {
    key: 'hardware',
    label: 'Hardware',
    group: 'peripherals',
    fields: [
      { key: 'hardware.enabled', label: 'Enabled', type: 'toggle', default: false },
      { key: 'hardware.transport', label: 'Transport', type: 'select', options: ['none', 'native', 'serial', 'probe'], default: 'none' },
      { key: 'hardware.serial_port', label: 'Serial Port', type: 'text' },
      { key: 'hardware.baud_rate', label: 'Baud Rate', type: 'number', min: 1 },
      { key: 'hardware.probe_target', label: 'Probe Target', type: 'text' },
      { key: 'hardware.workspace_datasheets', label: 'Workspace Datasheets', type: 'toggle', default: false },
    ]
  },
  {
    key: 'tunnel',
    label: 'Tunnel',
    group: 'general',
    fields: [
      { key: 'tunnel.provider', label: 'Provider', type: 'text' },
      { key: 'tunnel.ngrok.auth_token', label: 'Ngrok Auth Token', type: 'password' },
      { key: 'tunnel.ngrok.domain', label: 'Ngrok Domain', type: 'text' },
      { key: 'tunnel.cloudflare.token', label: 'Cloudflare Token', type: 'password' },
      { key: 'tunnel.custom.start_command', label: 'Custom Start Command', type: 'text' },
      { key: 'tunnel.custom.url_pattern', label: 'Custom URL Pattern', type: 'text' },
      { key: 'tunnel.custom.health_url', label: 'Custom Health URL', type: 'text' },
      { key: 'tunnel.tailscale.hostname', label: 'Tailscale Hostname', type: 'text' },
      { key: 'tunnel.tailscale.funnel', label: 'Tailscale Funnel', type: 'toggle', default: false },
    ]
  },
  {
    key: 'memory_profile',
    label: 'Profile & Backend',
    group: 'memory',
    fields: [
      { key: 'memory.profile', label: 'Profile', type: 'select', options: memoryProfileOptions, default: 'hybrid_keyword', hint: 'Preset convenience profile. Explicit field overrides still win.' },
      { key: 'memory.backend', label: 'Backend', type: 'text', default: 'hybrid', hint: 'Examples: hybrid, sqlite, postgres, markdown, redis, api, clickhouse, none' },
      { key: 'memory.instance_id', label: 'Instance ID', type: 'text' },
      { key: 'memory.auto_save', label: 'Auto Save', type: 'toggle', default: true },
      { key: 'memory.citations', label: 'Citations', type: 'text', default: 'auto' },
    ]
  },
  {
    key: 'memory_storage',
    label: 'Storage Backends',
    group: 'memory',
    fields: [
      { key: 'memory.postgres.url', label: 'Postgres URL', type: 'text' },
      { key: 'memory.postgres.schema', label: 'Postgres Schema', type: 'text', default: 'public' },
      { key: 'memory.postgres.table', label: 'Postgres Table', type: 'text', default: 'memories' },
      { key: 'memory.postgres.connect_timeout_secs', label: 'Postgres Connect Timeout (secs)', type: 'number', default: 30, min: 0 },
      { key: 'memory.redis.host', label: 'Redis Host', type: 'text', default: '127.0.0.1' },
      { key: 'memory.redis.port', label: 'Redis Port', type: 'number', default: 6379, min: 0 },
      { key: 'memory.redis.password', label: 'Redis Password', type: 'password' },
      { key: 'memory.redis.db_index', label: 'Redis DB Index', type: 'number', default: 0, min: 0 },
      { key: 'memory.redis.key_prefix', label: 'Redis Key Prefix', type: 'text', default: 'nullclaw' },
      { key: 'memory.redis.ttl_seconds', label: 'Redis TTL (secs)', type: 'number', default: 0, min: 0 },
      { key: 'memory.api.url', label: 'API URL', type: 'text' },
      { key: 'memory.api.api_key', label: 'API Key', type: 'password' },
      { key: 'memory.api.timeout_ms', label: 'API Timeout (ms)', type: 'number', default: 10000, min: 0 },
      { key: 'memory.api.namespace', label: 'API Namespace', type: 'text' },
      { key: 'memory.clickhouse.host', label: 'ClickHouse Host', type: 'text', default: '127.0.0.1' },
      { key: 'memory.clickhouse.port', label: 'ClickHouse Port', type: 'number', default: 8123, min: 0 },
      { key: 'memory.clickhouse.database', label: 'ClickHouse Database', type: 'text', default: 'default' },
      { key: 'memory.clickhouse.table', label: 'ClickHouse Table', type: 'text', default: 'memories' },
      { key: 'memory.clickhouse.user', label: 'ClickHouse User', type: 'text' },
      { key: 'memory.clickhouse.password', label: 'ClickHouse Password', type: 'password' },
      { key: 'memory.clickhouse.use_https', label: 'ClickHouse HTTPS', type: 'toggle', default: false },
    ]
  },
  {
    key: 'memory_qmd',
    label: 'QMD',
    group: 'memory',
    fields: [
      { key: 'memory.qmd.enabled', label: 'Enabled', type: 'toggle', default: false },
      { key: 'memory.qmd.command', label: 'Command', type: 'text', default: 'qmd' },
      { key: 'memory.qmd.search_mode', label: 'Search Mode', type: 'text', default: 'search' },
      { key: 'memory.qmd.include_default_memory', label: 'Include Default Memory', type: 'toggle', default: true },
      { key: 'memory.qmd.mcporter.enabled', label: 'Mcporter Enabled', type: 'toggle', default: false },
      { key: 'memory.qmd.mcporter.server_name', label: 'Mcporter Server Name', type: 'text', default: 'qmd' },
      { key: 'memory.qmd.mcporter.start_daemon', label: 'Mcporter Start Daemon', type: 'toggle', default: true },
      {
        key: 'memory.qmd.paths',
        label: 'Index Paths',
        type: 'json',
        default: [],
        hint: 'Workspace markdown locations indexed by the QMD helper.',
        editorKind: 'object-list',
        addLabel: 'Add Index Path',
        emptyLabel: 'No QMD index paths configured.',
        itemFields: [
          { key: 'name', path: 'memory.qmd.paths[*].name', label: 'Name', type: 'text' },
          { key: 'path', path: 'memory.qmd.paths[*].path', label: 'Path', type: 'text' },
          { key: 'pattern', path: 'memory.qmd.paths[*].pattern', label: 'Pattern', type: 'text', default: '**/*.md' },
        ],
      },
      { key: 'memory.qmd.sessions.enabled', label: 'Session Export Enabled', type: 'toggle', default: false },
      { key: 'memory.qmd.sessions.export_dir', label: 'Session Export Directory', type: 'text' },
      { key: 'memory.qmd.sessions.retention_days', label: 'Session Retention (days)', type: 'number', default: 30, min: 0 },
      { key: 'memory.qmd.update.interval_ms', label: 'Update Interval (ms)', type: 'number', default: 300000, min: 0 },
      { key: 'memory.qmd.update.debounce_ms', label: 'Update Debounce (ms)', type: 'number', default: 15000, min: 0 },
      { key: 'memory.qmd.update.on_boot', label: 'Update On Boot', type: 'toggle', default: true },
      { key: 'memory.qmd.update.wait_for_boot_sync', label: 'Wait For Boot Sync', type: 'toggle', default: false },
      { key: 'memory.qmd.update.embed_interval_ms', label: 'Embed Interval (ms)', type: 'number', default: 3600000, min: 0 },
      { key: 'memory.qmd.update.command_timeout_ms', label: 'Command Timeout (ms)', type: 'number', default: 30000, min: 0 },
      { key: 'memory.qmd.update.update_timeout_ms', label: 'Update Timeout (ms)', type: 'number', default: 120000, min: 0 },
      { key: 'memory.qmd.update.embed_timeout_ms', label: 'Embed Timeout (ms)', type: 'number', default: 120000, min: 0 },
      { key: 'memory.qmd.limits.max_results', label: 'Max Results', type: 'number', default: 6, min: 0 },
      { key: 'memory.qmd.limits.max_snippet_chars', label: 'Max Snippet Chars', type: 'number', default: 700, min: 0 },
      { key: 'memory.qmd.limits.max_injected_chars', label: 'Max Injected Chars', type: 'number', default: 4000, min: 0 },
      { key: 'memory.qmd.limits.timeout_ms', label: 'Query Timeout (ms)', type: 'number', default: 4000, min: 0 },
    ]
  },
  {
    key: 'memory_search',
    label: 'Search',
    group: 'memory',
    fields: [
      { key: 'memory.search.enabled', label: 'Enabled', type: 'toggle', default: true },
      { key: 'memory.search.provider', label: 'Provider', type: 'text', default: 'none' },
      { key: 'memory.search.model', label: 'Model', type: 'text', default: 'text-embedding-3-small' },
      { key: 'memory.search.dimensions', label: 'Dimensions', type: 'number', default: 1536, min: 1 },
      { key: 'memory.search.fallback_provider', label: 'Fallback Provider', type: 'text', default: 'none' },
      { key: 'memory.search.store.kind', label: 'Store Kind', type: 'select', options: memoryStoreKindOptions, default: 'auto' },
      { key: 'memory.search.store.sidecar_path', label: 'Store Sidecar Path', type: 'text' },
      { key: 'memory.search.store.qdrant_url', label: 'Qdrant URL', type: 'text' },
      { key: 'memory.search.store.qdrant_api_key', label: 'Qdrant API Key', type: 'password' },
      { key: 'memory.search.store.qdrant_collection', label: 'Qdrant Collection', type: 'text', default: 'nullclaw_memories' },
      { key: 'memory.search.store.pgvector_table', label: 'PGVector Table', type: 'text', default: 'memory_embeddings' },
      { key: 'memory.search.store.ann_candidate_multiplier', label: 'ANN Candidate Multiplier', type: 'number', default: 12, min: 0 },
      { key: 'memory.search.store.ann_min_candidates', label: 'ANN Min Candidates', type: 'number', default: 64, min: 0 },
      { key: 'memory.search.chunking.overlap', label: 'Chunk Overlap', type: 'number', default: 64, min: 0 },
      { key: 'memory.search.sync.mode', label: 'Sync Mode', type: 'select', options: memorySyncModeOptions, default: 'best_effort' },
      { key: 'memory.search.sync.embed_timeout_ms', label: 'Embed Timeout (ms)', type: 'number', default: 15000, min: 0 },
      { key: 'memory.search.sync.vector_timeout_ms', label: 'Vector Timeout (ms)', type: 'number', default: 5000, min: 0 },
      { key: 'memory.search.sync.embed_max_retries', label: 'Embed Retries', type: 'number', default: 2, min: 0 },
      { key: 'memory.search.sync.vector_max_retries', label: 'Vector Retries', type: 'number', default: 2, min: 0 },
      { key: 'memory.search.query.max_results', label: 'Query Max Results', type: 'number', default: 6, min: 0 },
      { key: 'memory.search.query.min_score', label: 'Query Min Score', type: 'number', default: 0, min: 0, step: 0.01 },
      { key: 'memory.search.query.merge_strategy', label: 'Merge Strategy', type: 'text', default: 'rrf' },
      { key: 'memory.search.query.rrf_k', label: 'RRF K', type: 'number', default: 60, min: 0 },
      { key: 'memory.search.query.hybrid.enabled', label: 'Hybrid Retrieval', type: 'toggle', default: false },
      { key: 'memory.search.query.hybrid.vector_weight', label: 'Hybrid Vector Weight', type: 'number', default: 0.7, min: 0, max: 1, step: 0.05 },
      { key: 'memory.search.query.hybrid.text_weight', label: 'Hybrid Text Weight', type: 'number', default: 0.3, min: 0, max: 1, step: 0.05 },
      { key: 'memory.search.query.hybrid.candidate_multiplier', label: 'Hybrid Candidate Multiplier', type: 'number', default: 4, min: 0 },
      { key: 'memory.search.query.hybrid.mmr.enabled', label: 'MMR Enabled', type: 'toggle', default: false },
      { key: 'memory.search.query.hybrid.mmr.lambda', label: 'MMR Lambda', type: 'number', default: 0.7, min: 0, max: 1, step: 0.05 },
      { key: 'memory.search.query.hybrid.temporal_decay.enabled', label: 'Temporal Decay Enabled', type: 'toggle', default: false },
      { key: 'memory.search.query.hybrid.temporal_decay.half_life_days', label: 'Temporal Decay Half-life (days)', type: 'number', default: 30, min: 0 },
      { key: 'memory.search.cache.enabled', label: 'Embedding Cache Enabled', type: 'toggle', default: true },
      { key: 'memory.search.cache.max_entries', label: 'Embedding Cache Max Entries', type: 'number', default: 10000, min: 0 },
    ]
  },
  {
    key: 'memory_retrieval',
    label: 'Retrieval Stages',
    group: 'memory',
    fields: [
      { key: 'memory.retrieval_stages.query_expansion_enabled', label: 'Query Expansion Enabled', type: 'toggle', default: false },
      { key: 'memory.retrieval_stages.adaptive_retrieval_enabled', label: 'Adaptive Retrieval Enabled', type: 'toggle', default: false },
      { key: 'memory.retrieval_stages.adaptive_keyword_max_tokens', label: 'Adaptive Keyword Max Tokens', type: 'number', default: 3, min: 0 },
      { key: 'memory.retrieval_stages.adaptive_vector_min_tokens', label: 'Adaptive Vector Min Tokens', type: 'number', default: 6, min: 0 },
      { key: 'memory.retrieval_stages.llm_reranker_enabled', label: 'LLM Reranker Enabled', type: 'toggle', default: false },
      { key: 'memory.retrieval_stages.llm_reranker_max_candidates', label: 'LLM Reranker Max Candidates', type: 'number', default: 10, min: 0 },
      { key: 'memory.retrieval_stages.llm_reranker_timeout_ms', label: 'LLM Reranker Timeout (ms)', type: 'number', default: 5000, min: 0 },
    ]
  },
  {
    key: 'memory_lifecycle',
    label: 'Lifecycle',
    group: 'memory',
    fields: [
      { key: 'memory.lifecycle.hygiene_enabled', label: 'Hygiene Enabled', type: 'toggle', default: true },
      { key: 'memory.lifecycle.archive_after_days', label: 'Archive After (days)', type: 'number', default: 7, min: 0 },
      { key: 'memory.lifecycle.purge_after_days', label: 'Purge After (days)', type: 'number', default: 30, min: 0 },
      { key: 'memory.lifecycle.preserve_before_purge', label: 'Preserve Before Purge', type: 'toggle', default: true },
      { key: 'memory.lifecycle.conversation_retention_days', label: 'Conversation Retention (days)', type: 'number', default: 30, min: 0 },
      { key: 'memory.lifecycle.snapshot_enabled', label: 'Snapshot Enabled', type: 'toggle', default: false },
      { key: 'memory.lifecycle.snapshot_on_hygiene', label: 'Snapshot On Hygiene', type: 'toggle', default: false },
      { key: 'memory.lifecycle.auto_hydrate', label: 'Auto Hydrate', type: 'toggle', default: true },
    ]
  },
  {
    key: 'memory_reliability',
    label: 'Reliability',
    group: 'memory',
    fields: [
      { key: 'memory.reliability.rollout_mode', label: 'Rollout Mode', type: 'select', options: memoryRolloutModeOptions, default: 'off' },
      { key: 'memory.reliability.circuit_breaker_failures', label: 'Circuit Breaker Failures', type: 'number', default: 5, min: 0 },
      { key: 'memory.reliability.circuit_breaker_cooldown_ms', label: 'Circuit Breaker Cooldown (ms)', type: 'number', default: 30000, min: 0 },
      { key: 'memory.reliability.shadow_hybrid_percent', label: 'Shadow Hybrid Percent', type: 'number', default: 0, min: 0, max: 100 },
      { key: 'memory.reliability.canary_hybrid_percent', label: 'Canary Hybrid Percent', type: 'number', default: 0, min: 0, max: 100 },
      { key: 'memory.reliability.fallback_policy', label: 'Fallback Policy', type: 'select', options: memoryFallbackPolicyOptions, default: 'degrade' },
    ]
  },
  {
    key: 'memory_cache',
    label: 'Response Cache',
    group: 'memory',
    fields: [
      { key: 'memory.response_cache.enabled', label: 'Enabled', type: 'toggle', default: false },
      { key: 'memory.response_cache.ttl_minutes', label: 'TTL (mins)', type: 'number', default: 60, min: 0 },
      { key: 'memory.response_cache.max_entries', label: 'Max Entries', type: 'number', default: 5000, min: 0 },
    ]
  },
  {
    key: 'memory_summarizer',
    label: 'Summarizer',
    group: 'memory',
    fields: [
      { key: 'memory.summarizer.enabled', label: 'Enabled', type: 'toggle', default: false },
      { key: 'memory.summarizer.window_size_tokens', label: 'Window Size Tokens', type: 'number', default: 4000, min: 0 },
      { key: 'memory.summarizer.summary_max_tokens', label: 'Summary Max Tokens', type: 'number', default: 500, min: 0 },
      { key: 'memory.summarizer.auto_extract_semantic', label: 'Auto Extract Semantic', type: 'toggle', default: true },
    ]
  },
  {
    key: 'advanced_maps',
    label: 'Advanced Maps',
    group: 'advanced',
    fields: [
      { key: 'mcp_servers', label: 'MCP Servers', type: 'text', hint: 'Raw JSON object string' },
      { key: 'model_routes', label: 'Model Routes', type: 'text', hint: 'Raw JSON object string' },
      { key: 'secrets.encrypt', label: 'Secrets Encrypt', type: 'text' },
      { key: 'workspace', label: 'Workspace', type: 'text', hint: 'Workspace root path' },
    ]
  }
];

export const staticSections: SectionDef[] = rawStaticSections.map(normalizeConfigSection);
export const memorySections: SectionDef[] = staticSections.filter((section) => section.group === 'memory');
