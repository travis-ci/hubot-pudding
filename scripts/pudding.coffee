# Description:
#   interact with a pudding server
#
# Dependencies:
#   sprintf
#   hubot-slack-attachment
#
# Configuration:
#   HUBOT_PUDDING_HOST
#   HUBOT_PUDDING_CHANNEL_WHITELIST
#   HUBOT_PUDDING_AUTH_TOKEN
#   HUBOT_PUDDING_DEFAULT_ROLE
#   HUBOT_PUDDING_ORG_STAGING_DEFAULT_INSTANCE_TYPE
#   HUBOT_PUDDING_ORG_PROD_DEFAULT_INSTANCE_TYPE
#   HUBOT_PUDDING_COM_STAGING_DEFAULT_INSTANCE_TYPE
#   HUBOT_PUDDING_COM_PROD_DEFAULT_INSTANCE_TYPE
#
# Commands:
#   hubot start instance in org staging - Start an instance in the org site staging env with defaults
#   hubot start instance in org staging with instance_type=c3.4xlarge - Start an instance in the org site staging env with with an override for instance_type
#   hubot start instance in org staging with count=1 instance_type=c3.4xlarge queue=docker role=worker - Start an instance running two containers in the org site staging environment with overrides for count (concurrency), instance_type, queue, and role
#   hubot list instances in org staging - List instances in a specific site->env
#   hubot list instances in org staging order by launch_time - List instances in a specific site->env ordered by an instance attribute
#   hubot list all instances - List instances in all sites and envs
#   hubot list instances - List instances in all sites and envs
#   hubot list all instances order by instance_type - List instances in all sites and envs ordered by an instance attribute
#   hubot summarize instances - Summarize all known instances
#   hubot where do instances live - List the site->env combinations where instances may be started
#   hubot what are the instance defaults - Show the default values for each site->env combination
#   hubot terminate instance i-abcd1234 - Terminate a instance by instance id
#   hubot who can do stuff with instances - Show the whitelisted channels with access to instance actions
#   hubot list images - List all images
#   hubot list images for worker - List all images for role worker
#   hubot list active images - Lits all active images

util = require 'util'
{sprintf} = require 'sprintf'

host = process.env.HUBOT_PUDDING_HOST
token = process.env.HUBOT_PUDDING_AUTH_TOKEN
whitelisted_channels = (
  process.env.HUBOT_PUDDING_CHANNEL_WHITELIST || ''
).split(/\s*,\s*/).sort()
default_role = process.env.HUBOT_PUDDING_DEFAULT_ROLE || ''

defaults =
  sites: ['org', 'com']
  envs: ['prod', 'staging']
  org:
    staging:
      instance_type: process.env.HUBOT_PUDDING_ORG_STAGING_DEFAULT_INSTANCE_TYPE || 'c3.2xlarge'
      queue: 'docker'
      subnet_id: process.env.HUBOT_PUDDING_ORG_STAGING_DEFAULT_SUBNET_ID
      security_group_id: process.env.HUBOT_PUDDING_ORG_STAGING_DEFAULT_SECURITY_GROUP_ID
    prod:
      instance_type: process.env.HUBOT_PUDDING_ORG_PROD_DEFAULT_INSTANCE_TYPE ||'c3.4xlarge'
      queue: 'docker'
      subnet_id: process.env.HUBOT_PUDDING_ORG_PROD_DEFAULT_SUBNET_ID
      security_group_id: process.env.HUBOT_PUDDING_ORG_PROD_DEFAULT_SECURITY_GROUP_ID
  com:
    staging:
      instance_type: process.env.HUBOT_PUDDING_COM_STAGING_DEFAULT_INSTANCE_TYPE || 'c3.2xlarge'
      queue: 'docker'
      subnet_id: process.env.HUBOT_PUDDING_COM_STAGING_DEFAULT_SUBNET_ID
      security_group_id: process.env.HUBOT_PUDDING_COM_STAGING_DEFAULT_SECURITY_GROUP_ID
    prod:
      instance_type: process.env.HUBOT_PUDDING_COM_PROD_DEFAULT_INSTANCE_TYPE ||'c3.4xlarge'
      queue: 'docker'
      subnet_id: process.env.HUBOT_PUDDING_COM_PROD_DEFAULT_SUBNET_ID
      security_group_id: process.env.HUBOT_PUDDING_COM_PROD_DEFAULT_SECURITY_GROUP_ID
  counts:
    'c3.2xlarge': 4
    'c3.4xlarge': 8
    'c3.8xlarge': 16
  role: default_role

module.exports = (robot) ->
  if !host
    robot.logger.warning('Missing HUBOT_PUDDING_HOST')
  if !token
    robot.logger.warning('Missing HUBOT_PUDDING_AUTH_TOKEN')

  whitelist_respond robot, /who can do stuff with instances/i, (_, msg) ->
    msg.send "The whitelisted channels are: *#{whitelisted_channels.join("*, *")}*"

  whitelist_respond robot, /where do instances live/i, (_, msg) ->
    response = "instances live in"
    defaults.sites.map (site) ->
      defaults.envs.map (env) ->
        response += " *#{site} #{env}*,"

    msg.send response.replace(/, ([^,]+),$/, ', and $1')

  whitelist_respond robot, /what are the instance defaults/i, (_, msg) ->
    msg.send "```\n#{util.inspect(defaults)}\n```"

  whitelist_respond robot, /start instance [io]n ([a-z]+) ([a-z]+)$/i, start_instance_response()

  whitelist_respond robot, /start instance [io]n ([a-z]+) ([a-z]+) with (.+)/i, start_instance_response()

  whitelist_respond robot, /sum(marize)? instances/i, (robot, msg) ->
    list_instances robot, host, '', '', default_role, token, send_instances_summary_cb(robot, msg)

  whitelist_respond robot, /terminate instance (i-[a-z0-9]{8})/i, (robot, msg) ->
    instance_id = msg.match[1]
    channel = msg.envelope.room
    terminate_instance robot, host, token, instance_id, channel, (err) ->
      if err
        msg.send err
        return
      msg.send "Sent termination request for *#{instance_id}*"

  whitelist_respond robot, /list (all )?instances$/i, (robot, msg) ->
    list_instances robot, host, '', '', default_role, token, send_instances_list_cb(msg)

  whitelist_respond robot, /list all instances order by (.+)/i, (robot, msg) ->
    list_instances robot, host, '', '', default_role, token, send_instances_list_cb(msg, msg.match[1])

  whitelist_respond robot, /list instances [io]n ([a-z]+) ([a-z]+)$/i, (robot, msg) ->
    list_instances robot, host, msg.match[1], msg.match[2], default_role, token, send_instances_list_cb(msg)

  whitelist_respond robot, /list instances [io]n ([a-z]+) ([a-z]+) order by (.+)/i, (robot, msg) ->
    list_instances robot, host, msg.match[1], msg.match[2], default_role, token, send_instances_list_cb(msg, msg.match[3])

  whitelist_respond robot, /list images$/i, (robot, msg) ->
    list_images robot, host, '', '', token, send_images_list_cb(msg)

  whitelist_respond robot, /list images for ([a-z]+)$/i, (robot, msg) ->
    list_images robot, host, msg.match[1], '', token, send_images_list_cb(msg)

  whitelist_respond robot, /list active images/i, (robot, msg) ->
    list_images robot, host, '', 'true', token, send_images_list_cb(msg)

whitelist_respond = (robot, pattern, cb) ->
  robot.respond pattern, (msg) ->
    if whitelisted_channels.indexOf(msg.envelope.room) > -1
      return cb(robot, msg)
    robot.logger.warning("channel #{msg.envelope.room} is not in the whitelist!")

format_instance = (instance) ->
  sprintf(
    "%(id)s:  %(instance_type)s  %(launch_time)s  %(ip)-15s %(private_ip)-15s\t%(name)s\n", instance
  )

build_instance_cfg = (site, env, opts) ->
  cfg =
    opts:
      instance_type: get_site_default('instance_type', site, env)
      queue: get_site_default('queue', site, env)
      count: defaults.counts[get_site_default('instance_type', site, env)]
      role: default_role
      subnet_id: get_site_default('subnet_id', site, env)
      security_group_id: get_site_default('security_group_id', site, env)
    site: site
    env: env

  given_opts = {}
  raw_opts = (opts || '').replace(/^\s*with\s+/i, '')
  raw_opts.split(/\s+/).map (pair) ->
    pair_parts = pair.split('=')
    if pair_parts.length > 1
      [key, value] = [pair_parts[0].trim(), pair_parts[1].trim()]
      cfg.opts[key] = value
      given_opts[key] = 1

  if given_opts.instance_type and not given_opts.count
    cfg.opts.count = defaults.counts[cfg.opts.instance_type]

  cfg.inspected_opts = util.inspect(cfg.opts).replace(/\n/g, ' ')
  cfg

get_site_default = (key, site, env) ->
  ((defaults[site] || {})[env] || {})[key]

send_instances_summary_cb = (robot, msg) ->
  return (err, instances) ->
    if err
      msg.send err
      return

    fields = []
    defaults.sites.map (site) ->
      defaults.envs.map (env) ->
        fields.push
          title: "#{site} #{env}"
          value: format_instance_totals_in_site_env(site, env, instances)
          short: true

    payload =
      message: msg.message
      content:
        text: ''
        fallback: 'Instances'
        pretext: "All #{default_role} instances"
        color: '#77cc77'
        fields: fields
      username: robot.name

    robot.emit 'slack.attachment', payload

format_instance_totals_in_site_env = (site, env, instances) ->
  totals = get_instance_totals_in_site_env(site, env, instances)
  resp = ''
  Object.keys(totals).map (instance_type) ->
    capacity = (defaults.counts[instance_type] || 0) * totals[instance_type]
    resp += "#{instance_type}: *#{totals[instance_type]}* (capacity *#{capacity}*)"
  resp

get_instance_totals_in_site_env = (site, env, instances) ->
  totals = {}
  instances.map (inst) ->
    if inst.site == site and inst.env == env
      totals[inst.instance_type] ||= 0
      totals[inst.instance_type] = totals[inst.instance_type] + 1

  totals

send_instances_list_cb = (msg, orderby) ->
  return (err, instances) ->
    if err
      msg.send err
      return

    orderby ?= 'launch_time'
    instances.sort (a, b) ->
      if a[orderby] > b[orderby]
        return 1
      return -1

    response = '```\n'

    instances.map (inst) ->
      if not inst.ip or inst.ip is ''
        inst.ip = '_'
      response += format_instance(inst)

    msg.send response + '```'

list_instances = (robot, host, site, env, role, token, cb) ->
  robot.http("#{host}/instances?site=#{site}&env=#{env}&role=#{role}")
    .header('Authorization', "token #{token}")
    .get() (err, res, body) ->
      if err
        cb "Oh No!  Failed to get the current instances"
        return

      if res.statusCode isnt 200
        cb "Oh No!  The server respondend *#{res.statusCode}*"
        return

      body_json = null
      try
        body_json = JSON.parse(body)
      catch error
        cb "Oh No!  Couldn't parse the JSON response! *#{error}* _body=#{body}_"
        return

      cb null, body_json['instances']

start_instance_response = ->
  return (robot, msg) ->
    cfg = build_instance_cfg(msg.match[1], msg.match[2], msg.match[3])
    cfg.channel = msg.envelope.room
    msg.send sprintf("Spinning up instance in site=*%(site)s* " +
                     "env=*%(env)s* with _opts=%(inspected_opts)s_", cfg)

    start_instance robot, host, token, cfg, (err, response) ->
      if err
        msg.send err
        return
      msg.send response

start_instance = (robot, host, token, cfg, cb) ->
  data = JSON.stringify({
    instance_builds:
      site: cfg.site
      env: cfg.env
      role: cfg.opts.role
      ami: cfg.opts.ami || ''
      instance_type: cfg.opts.instance_type
      count: parseInt(cfg.opts.count)
      queue: cfg.opts.queue
      subnet_id: cfg.opts.subnet_id
      security_group_id: cfg.opts.security_group_id
  })
  robot.http("#{host}/instance-builds?slack-channel=#{cfg.channel}")
    .header('Authorization', "token #{token}")
    .post(data) (err, res, body) ->
      if err
        cb "Failed to start instance build! *#{err}*"
        return

      if res.statusCode isnt 202
        cb "Failed to start instance build! *#{res.statusCode}* _body=#{body}_"
        return

      body_json = null
      try
        body_json = JSON.parse(body)
      catch error
        cb "Couldn't parse the instance build response! *#{error}* _body=#{body}_"
        return

      instance_build = body_json.instance_builds[0]
      cb null, "Started instance build *#{instance_build.id}*", instance_build

terminate_instance = (robot, host, token, instance_id, channel, cb) ->
  robot.http("#{host}/instances/#{instance_id}?slack-channel=#{channel}")
    .header('Authorization', "token #{token}")
    .delete() (err, res, body) ->
      if err
        cb "Failed to send termination request for *#{instance_id}*: *#{err}*"
        return

      if res.statusCode isnt 202
        cb "Failed to send termination request for *#{instance_id}*: _status=#{res.statusCode}_"
        return

      cb null

format_image = (image) ->
  if image.active
    sprintf("%(image_id)s: role=%(role)s\t%(name)s (ACTIVE)\n", image)
  else
    sprintf("%(image_id)s: role=%(role)s\t%(name)s\n", image)

send_images_list_cb = (msg) ->
  return (err, images) ->
    if err
      msg.send err
      return

    images.sort (a, b) ->
      if a.role > b.role
        return 1
      return -1

    response = '```\n'

    images.map (img) ->
      response += format_image(img)

    msg.send response + '```'

list_images = (robot, host, role, active, token, cb) ->
  robot.http("#{host}/images?role=#{role}&active=#{active}")
    .header('Authorization', "token #{token}")
    .get() (err, res, body) ->
      if err
        cb "Oh No!  Failed to get the current images"
        return

      if res.statusCode isnt 200
        cb "Oh No!  The server responded *#{res.statusCode}*"
        return

      body_json = null
      try
        body_json = JSON.parse(body)
      catch error
        cb "Oh No!  Couldn't parse the JSON response! *#{error}* _body=#{body}_"
        return

      cb null, body_json['images']
