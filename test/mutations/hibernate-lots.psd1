# Mutations of the lot half of fleet/Hibernate.ps1: a hibernate run is one lot of tier 2, reason hibernate (T-0216). test/test-fleet-hibernate.ps1 must fail a check for every one. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\hibernate-lots.psd1
@{
    Target = "fleet\Hibernate.ps1"
    Suite  = "test\test-fleet-hibernate.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "lot-members-lose-their-tier"
           Find = '-By $caller -Why $lotWhy -Tier $Tier'
           Replace = '-By $caller -Why $lotWhy' }
        @{ Name = "lot-reason-is-not-the-hibernate"
           Find = '$lotWhy = "hibernate tier "'
           Replace = '$lotWhy = "park tier "' }
    )
}
