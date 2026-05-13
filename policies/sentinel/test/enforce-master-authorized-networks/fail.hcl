mock "tfplan/v2" {
  module {
    source = "../../testdata/tfplan-noncompliant.sentinel"
  }
}

test {
  rules = {
    main = false
  }
}

