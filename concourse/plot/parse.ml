open Lwt
open Lwt.Infix

let file = "resources.json"

type github = Release | Pr | Git | Status | Webhook

type ci = Concourse_semver_tag | Keyval | Time

type docker = Image | Registry

type slack = Alert | Notification

type misc = Cogito | Infra_runner | Rss_resources | S3 | Terraform

type resource =
  | Github of github
  | Docker of docker
  | Slack of slack
  | Ci of ci
  | Misc of misc
  | Unknown of string

let to_type = function
  | "cogito" -> Misc Cogito
  | "concourse-git-semver-tag" -> Ci Concourse_semver_tag
  | "docker-image" -> Docker Image
  | "git" -> Github Git
  | "github-release" -> Github Release
  | "github-status" -> Github Status
  | "github-webhook" -> Github Webhook
  | "infra-runner" -> Misc Infra_runner
  | "keyval" -> Ci Keyval
  | "pull-request" -> Github Pr
  | "registry-image" -> Docker Registry
  | "rss-resource" -> Misc Rss_resources
  | "s3" -> Misc S3
  | "slack-alert" -> Slack Alert
  | "slack-notification" -> Slack Notification
  | "terraform" -> Misc Terraform
  | "time" -> Ci Time
  | i -> Unknown i

let of_type = function
  | Misc i -> (
    match i with
    | Cogito -> "cogito"
    | Infra_runner -> "infra-runner"
    | Rss_resources -> "rss-resource"
    | S3 -> "s3"
    | Terraform -> "terraform" )
  | Slack i -> (
    match i with
    | Alert -> "slack-alert"
    | Notification -> "slack-notification" )
  | Ci i -> (
    match i with
    | Concourse_semver_tag -> "concourse-git-semver-tag"
    | Keyval -> "keyval"
    | Time -> "time" )
  | Docker i -> (
    match i with
    | Image -> "docker-image"
    | Registry -> "registry" )
  | Github i -> (
    match i with
    | Release -> "github-release"
    | Pr -> "pull-request"
    | Git -> "git"
    | Status -> "github-status"
    | Webhook -> "github-webhook" )
  | Unknown i -> i

type resources = {name: string; resource: resource}

type data = resources list

type pipeline = {pipeline: string; resources: resources list}

type team = {team: string; pipelines: pipeline list}

module Json = struct
  let json_of_file =
    Lwt_io.with_file ~mode:Lwt_io.input file (fun ic -> Lwt_io.read ic)
    >>= fun i -> return (Yojson.Basic.from_string i)

  let type_of_json =
    let open Yojson.Basic.Util in
    Lwt_main.run json_of_file
    |> to_list
    |> List.map (fun i ->
           { team= member "team" i |> to_string
           ; pipelines=
               member "pipelines" i
               |> to_list
               |> List.map (fun i' ->
                      { pipeline= member "pipeline" i' |> to_string
                      ; resources=
                          member "resources" i'
                          |> to_list
                          |> List.map (fun i'' ->
                                 { name= member "name" i'' |> to_string
                                 ; resource=
                                     member "type" i'' |> to_string |> to_type
                                 }) }) })
end

module Team = struct
  type team_resource_stats = resource * int

  type team_stats = string * team_resource_stats list

  type resource_team_stats = string * int

  type resource_stats = string * resource_team_stats list

  type result = team_stats list * resource_stats list

  module M = Map.Make (struct
    type t = string * resource

    let compare = compare
  end)

  module F = Map.Make (struct
    type t = string

    let compare = compare
  end)

  let resources = []

  let team_stats = []

  let get_stats data =
    let rec walk_proj m = function
      | [] -> m
      | h :: t ->
          let rec aux_pipe m = function
            | [] -> m
            | h' :: t' -> aux_pipe (walk_resource m h'.resources) t'
          and walk_resource m = function
            | [] -> m
            | h' :: t' -> (
              match M.find_opt (h.team, h'.resource) m with
              | Some i ->
                  walk_resource (M.add (h.team, h'.resource) (i + 1) m) t'
              | None -> walk_resource (M.add (h.team, h'.resource) 0 m) t' )
          in
          walk_proj (aux_pipe m h.pipelines) t
    in
    let out f foo =
      (* absolute fucking dumpster fire, but it's not the end goal so whatever *)
      let f' = ref f in
      let wr path data =
        let%lwt fd =
          match F.find_opt path !f' with
          | None ->
              let%lwt i =
                Lwt_io.open_file
                  ~flags:[Lwt_unix.O_APPEND; Lwt_unix.O_CREAT; Lwt_unix.O_WRONLY]
                  ~mode:Lwt_io.output path
              in
              (* Lwt_io.write_line i "type,count" >>= fun _ -> (); *)
              f' := F.add path i !f' ;
              return i
          | Some i -> return i
        in
        Lwt_io.write_line fd data >>= fun _ -> return ();
      in
      M.iter
        (fun k v ->
          match k with
          | team, resource ->
              Lwt_main.run
                (wr
                   (String.concat "." [team; "csv"])
                   (String.concat "," [of_type resource; string_of_int v])))
        foo ;
        F.iter (fun _ v -> Lwt_main.run (Lwt_io.close v)) f
    in
    walk_proj M.empty data |> out F.empty
end

let go =
  let data = Json.type_of_json in
  Team.get_stats data

let () = go
