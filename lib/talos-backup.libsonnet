/**
 * Library with public helper methods provided by component talos-backup.
 */

local kube = import 'lib/kube.libjsonnet';

local talosApiGroup = 'talos.dev';

local TalosServiceAccount() = {
  apiVersion: '%s/v1alpha1' % talosApiGroup,
  kind: 'ServiceAccount',
  spec: {
    roles: [ 'os:etcd:backup' ],
  },
};

local S3CredentialsSecret(params) = kube.Secret(params.s3.credentials.name) {
  stringData: {
    AWS_ACCESS_KEY_ID: params.s3.credentials.access_key_id,
    AWS_SECRET_ACCESS_KEY: params.s3.credentials.secret_access_key,
  },
};

local image(params) =
  local i = params.images.talos_backup;
  '%s/%s:%s' % [ i.registry, i.repository, i.tag ];

local envFromParams(params) =
  local fromSecret(k) = {
    name: k,
    valueFrom: {
      secretKeyRef: {
        name: params.s3.credentials.name,
        key: k,
      },
    },
  };
  local kv(k, v) = { name: k, value: std.toString(v) };
  local optional(k, v) = if v != '' && v != null then [ kv(k, v) ] else [];
  [
    fromSecret('AWS_ACCESS_KEY_ID'),
    fromSecret('AWS_SECRET_ACCESS_KEY'),
    kv('AWS_REGION', params.s3.region),
    kv('BUCKET', params.s3.bucket),
    kv('USE_PATH_STYLE', params.s3.use_path_style),
    kv('ENABLE_COMPRESSION', params.enable_compression),
    // Set both env vars to the same value: upstream Split("", ",") returns
    // [""] from an unset var, poisoning the recipient list. Duplicates harmless.
    kv('AGE_RECIPIENT_PUBLIC_KEY', std.join(',', params.age_recipient_public_keys)),
    kv('AGE_X25519_PUBLIC_KEY', std.join(',', params.age_recipient_public_keys)),
  ]
  + optional('CUSTOM_S3_ENDPOINT', params.s3.endpoint)
  + optional('S3_PREFIX', params.s3.prefix)
  + optional('CLUSTER_NAME', params.cluster_name)
  + [ kv(k, params.extra_env[k]) for k in std.objectFields(params.extra_env) ];

local CronJob(params) = {
  apiVersion: 'batch/v1',
  kind: 'CronJob',
  spec: {
    schedule: params.schedule,
    concurrencyPolicy: params.concurrency_policy,
    successfulJobsHistoryLimit: params.successful_jobs_history_limit,
    failedJobsHistoryLimit: params.failed_jobs_history_limit,
    jobTemplate: {
      spec: {
        template: {
          spec: {
            restartPolicy: 'OnFailure',
            automountServiceAccountToken: false,
            securityContext: {
              runAsNonRoot: true,
              runAsUser: 1000,
              runAsGroup: 1000,
              fsGroup: 1000,
              seccompProfile: { type: 'RuntimeDefault' },
            },
            [if params.node_selector != {} then 'nodeSelector']: params.node_selector,
            [if params.tolerations != [] then 'tolerations']: params.tolerations,
            [if params.affinity != {} then 'affinity']: params.affinity,
            containers: [ {
              name: 'talos-backup',
              image: image(params),
              imagePullPolicy: params.images.talos_backup.pull_policy,
              workingDir: '/tmp',
              command: [ '/talos-backup' ],
              env: envFromParams(params),
              resources: params.resources,
              securityContext: {
                allowPrivilegeEscalation: false,
                readOnlyRootFilesystem: true,
                capabilities: { drop: [ 'ALL' ] },
              },
              volumeMounts: [
                { mountPath: '/tmp', name: 'tmp' },
                { mountPath: '/.talos', name: 'talos' },
                { mountPath: '/var/run/secrets/talos.dev', name: 'talos-secrets' },
              ],
            } ],
            volumes: [
              { name: 'tmp', emptyDir: {} },
              { name: 'talos', emptyDir: {} },
              {
                name: 'talos-secrets',
                secret: { secretName: params.talos_service_account.name },
              },
            ],
          },
        },
      },
    },
  },
};

{
  TalosServiceAccount: TalosServiceAccount,
  S3CredentialsSecret: S3CredentialsSecret,
  CronJob: CronJob,

  talosApiGroup: talosApiGroup,
}
