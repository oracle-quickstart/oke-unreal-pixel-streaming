resource "helm_release" "unreal_pixel_streaming_demo" {
  name      = "unreal-pixel-streaming-demo"
  chart     = "${path.module}/../helm-charts/charts/unreal-pixel-streaming-demo"
  namespace = "demo"

  depends_on = [module.oke-quickstart]

  count = var.unreal_pixel_streaming_demo ? 1 : 0
}