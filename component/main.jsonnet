// main template for talos-backup
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local lib = import 'talos-backup.libsonnet';
local inv = kap.inventory();
local params = inv.parameters.talos_backup;

local componentName = inv.parameters._instance;

assert
  std.length(params.age_recipient_public_keys) > 0
  : 'talos_backup: age_recipient_public_keys must contain at least one public key';
assert
  params.s3.bucket != ''
  : 'talos_backup: s3.bucket must be set';
assert
  !params.s3.credentials.create
  || (params.s3.credentials.access_key_id != '' && params.s3.credentials.secret_access_key != '')
  : 'talos_backup: s3.credentials.create=true requires access_key_id and secret_access_key';

local commonLabels = {
  'app.kubernetes.io/component': componentName,
  'app.kubernetes.io/managed-by': 'commodore',
  'app.kubernetes.io/part-of': 'syn',
};

local commonMetadata = {
  labels+: commonLabels,
};

local namespace = kube.Namespace(params.namespace.name) {
  metadata: commonMetadata + com.makeMergeable({
    name: params.namespace.name,
    annotations: params.namespace.annotations,
    labels: params.namespace.labels {
      'app.kubernetes.io/name': params.namespace.name,
    },
  }),
};

local talosServiceAccount = lib.TalosServiceAccount() {
  metadata: commonMetadata + com.makeMergeable({
    name: params.talos_service_account.name,
    namespace: params.namespace.name,
    labels: { 'app.kubernetes.io/name': params.talos_service_account.name },
  }),
};

local cronjob = lib.CronJob(params) {
  metadata: commonMetadata + com.makeMergeable({
    name: componentName,
    namespace: params.namespace.name,
    labels: { 'app.kubernetes.io/name': componentName },
  }),
};

local s3Secret = lib.S3CredentialsSecret(params) {
  metadata: commonMetadata + com.makeMergeable({
    name: params.s3.credentials.name,
    namespace: params.namespace.name,
    labels: { 'app.kubernetes.io/name': params.s3.credentials.name },
  }),
};

{
  '00_namespace': namespace,
  '10_talos_serviceaccount': talosServiceAccount,
  [if params.s3.credentials.create then '10_s3_credentials']: s3Secret,
  '20_cronjob': cronjob,
}
