export type FieldType = 'text' | 'password' | 'number' | 'toggle' | 'select' | 'list';

export interface FieldDef {
  key: string;
  label: string;
  type: FieldType;
  default?: any;
  options?: string[];
  step?: number;
  min?: number;
  max?: number;
  hint?: string;
  advanced?: boolean;
}

export interface ChannelSchema {
  label: string;
  hasAccounts: boolean;
  fields: FieldDef[];
}

export const channelSchemas: Record<string, ChannelSchema> = {
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
      { key: 'transport.timeout_ms', label: 'Transport Timeout (ms)', type: 'number', default: 30000 },
      { key: 'transport.env.PLUGIN_TOKEN', label: 'Transport Env: PLUGIN_TOKEN', type: 'password', advanced: true },
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
};

export interface SectionDef {
  key: string;
  label: string;
  fields: FieldDef[];
}

export const staticSections: SectionDef[] = [
  {
    key: 'models',
    label: 'Models & Providers',
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
      { key: 'reliability.model_fallbacks', label: 'Model Fallbacks', type: 'list', default: [], hint: 'One fallback rule per line' },
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
    fields: [
      { key: 'agent.max_tool_iterations', label: 'Max Tool Iterations', type: 'number', default: 25 },
      { key: 'agent.max_history_messages', label: 'Max History Messages', type: 'number', default: 50 },
      { key: 'agent.session_idle_timeout_secs', label: 'Session Idle Timeout (secs)', type: 'number', default: 1800 },
      { key: 'agent.parallel_tools', label: 'Parallel Tools', type: 'toggle', default: false },
      { key: 'agent.compact_context', label: 'Compact Context', type: 'toggle', default: false },
      { key: 'agent.message_timeout_secs', label: 'Message Timeout (secs)', type: 'number', default: 300 },
      { key: 'agent.auto_disable_vision_on_error', label: 'Auto Disable Vision On Error', type: 'toggle', default: false },
      { key: 'agent.status_show_emojis', label: 'Status Show Emojis', type: 'toggle', default: true },
      { key: 'agent.token_limit', label: 'Token Limit', type: 'number', min: 1 },
      { key: 'agent.tool_dispatcher', label: 'Tool Dispatcher', type: 'text' },
      { key: 'agent.compaction_keep_recent', label: 'Compaction Keep Recent', type: 'number', min: 0 },
      { key: 'agent.compaction_max_source_chars', label: 'Compaction Max Source Chars', type: 'number', min: 0 },
      { key: 'agent.compaction_max_summary_chars', label: 'Compaction Max Summary Chars', type: 'number', min: 0 },
      { key: 'agent.vision_disabled_models', label: 'Vision-disabled Models', type: 'list', default: [] },
    ]
  },
  {
    key: 'autonomy',
    label: 'Autonomy',
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
    fields: [
      { key: 'diagnostics.log_tool_calls', label: 'Log Tool Calls', type: 'toggle', default: true },
      { key: 'diagnostics.log_message_receipts', label: 'Log Message Receipts', type: 'toggle', default: true },
      { key: 'diagnostics.log_message_payloads', label: 'Log Message Payloads', type: 'toggle', default: false },
      { key: 'diagnostics.log_llm_io', label: 'Log LLM I/O', type: 'toggle', default: false },
      { key: 'diagnostics.backend', label: 'Diagnostics Backend', type: 'text' },
      { key: 'diagnostics.api_error_max_chars', label: 'API Error Max Chars', type: 'number', min: 0 },
      { key: 'diagnostics.otel.endpoint', label: 'OTEL Endpoint', type: 'text' },
      { key: 'diagnostics.otel.service_name', label: 'OTEL Service Name', type: 'text' },
      { key: 'diagnostics.otel.headers', label: 'OTEL Headers', type: 'text', hint: 'JSON object string' },
      { key: 'diagnostics.otel_endpoint', label: 'Legacy OTEL Endpoint', type: 'text' },
      { key: 'diagnostics.otel_service_name', label: 'Legacy OTEL Service Name', type: 'text' },
      { key: 'diagnostics.token_usage_ledger_enabled', label: 'Token Usage Ledger Enabled', type: 'toggle', default: false },
      { key: 'diagnostics.token_usage_ledger_max_bytes', label: 'Token Usage Ledger Max Bytes', type: 'number', min: 0 },
      { key: 'diagnostics.token_usage_ledger_max_lines', label: 'Token Usage Ledger Max Lines', type: 'number', min: 0 },
      { key: 'diagnostics.token_usage_ledger_window_hours', label: 'Token Usage Ledger Window (hours)', type: 'number', min: 0 },
    ]
  },
  {
    key: 'browser',
    label: 'Browser',
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
    fields: [
      { key: 'session.dm_scope', label: 'DM Scope', type: 'select', options: ['main', 'per_peer', 'per_channel_peer', 'per_account_channel_peer'], default: 'per_channel_peer' },
      { key: 'session.idle_minutes', label: 'Idle Minutes', type: 'number', default: 60, min: 1 },
      { key: 'session.typing_interval_secs', label: 'Typing Interval (secs)', type: 'number', default: 5, min: 1 },
      { key: 'session.max_concurrent_tasks', label: 'Max Concurrent Tasks', type: 'number', default: 4, min: 1 },
      { key: 'session.auto_provision_direct_agents', label: 'Auto Provision Direct Agents', type: 'toggle', default: false },
      { key: 'session.claim_secret', label: 'Claim Secret', type: 'password' },
      { key: 'session.claim_admin_secret', label: 'Claim Admin Secret', type: 'password' },
      { key: 'session.claim_max_attempts', label: 'Claim Max Attempts', type: 'number', default: 5, min: 1 },
      { key: 'session.claim_lockout_secs', label: 'Claim Lockout (secs)', type: 'number', default: 300, min: 1 },
    ]
  },
  {
    key: 'cost',
    label: 'Cost',
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
    fields: [
      { key: 'cron.enabled', label: 'Enabled', type: 'toggle', default: false },
      { key: 'cron.interval_minutes', label: 'Interval (mins)', type: 'number', min: 1 },
      { key: 'cron.max_run_history', label: 'Max Run History', type: 'number', min: 0 },
    ]
  },
  {
    key: 'scheduler',
    label: 'Scheduler',
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
    fields: [
      { key: 'identity.format', label: 'Format', type: 'text' },
      { key: 'identity.aieos_inline', label: 'AIEOS Inline', type: 'text' },
      { key: 'identity.aieos_path', label: 'AIEOS Path', type: 'text' },
    ]
  },
  {
    key: 'heartbeat',
    label: 'Heartbeat',
    fields: [
      { key: 'heartbeat.enabled', label: 'Enabled', type: 'toggle', default: false },
      { key: 'heartbeat.interval_minutes', label: 'Interval (mins)', type: 'number', min: 1 },
    ]
  },
  {
    key: 'a2a',
    label: 'A2A',
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
    fields: [
      { key: 'composio.enabled', label: 'Enabled', type: 'toggle', default: false },
      { key: 'composio.api_key', label: 'API Key', type: 'password' },
      { key: 'composio.entity_id', label: 'Entity ID', type: 'text' },
    ]
  },
  {
    key: 'hardware',
    label: 'Hardware',
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
    key: 'advanced_maps',
    label: 'Advanced Maps',
    fields: [
      { key: 'mcp_servers', label: 'MCP Servers', type: 'text', hint: 'Raw JSON object string' },
      { key: 'model_routes', label: 'Model Routes', type: 'text', hint: 'Raw JSON object string' },
      { key: 'secrets.encrypt', label: 'Secrets Encrypt', type: 'text' },
      { key: 'workspace', label: 'Workspace', type: 'text', hint: 'Workspace root path' },
    ]
  }
];
