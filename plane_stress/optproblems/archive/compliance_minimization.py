from mpi4py import MPI
import numpy as np
import matplotlib.pylab as plt
import plane_stress
from scipy import sparse
from scipy.sparse import linalg
from scipy.spatial import KDTree
import matplotlib.pylab as plt
import matplotlib.tri as tri
from paropt import ParOpt

class ComplianceMinimization(ParOpt.Problem):
    def __init__(self, conn, vars, X, force, r0, qval, C):
        """
        The constructor for the topology optimization class.

        This function sets up the data that is requried to perform a
        plane stress analysis of a square, plane stress structure.
        This is probably only useful for topology optimization.
        """

        # Save the data
        self.conn = conn
        self.vars = vars
        self.X = X
        self.force = force
        self.qval = qval
        self.C = C

        # Set the number of variables and the number of nodes
        self.nvars = np.max(self.vars) + 1
        self.nnodes = np.max(self.conn) + 1

        super(ComplianceMinimization, self).__init__(MPI.COMM_SELF, self.nnodes, 1)

        # Compute the non-zero pattern for the sparse matrix
        rowp = np.zeros(self.nvars+1, dtype=np.intc)
        cols = np.zeros(1, dtype=np.intc)

        # Compute the dimension of the cols array required
        ncols = plane_stress.computenzpattern(conn.T, vars.T, rowp, cols)

        # Allocate the required dimension of the cols array
        cols_temp = np.zeros(ncols, dtype=np.intc)
        plane_stress.computenzpattern(self.conn.T, self.vars.T, rowp, cols_temp)

        # Truncate the cols array to only include
        self.cols = np.zeros(rowp[-1], dtype=np.intc)
        self.cols[:] = cols_temp[:rowp[-1]]
        self.rowp = rowp

        # Allocate space for the entries of the matrix
        self.Kvals = np.zeros(self.cols.shape)

        # Compute the mass (area) of the structure with a full density
        rho = np.ones(self.nnodes)
        self.total_mass = plane_stress.computemass(self.conn.T, self.X.T, rho)

        # Now, compute the filter weights and store them as a sparse
        # matrix
        F = sparse.lil_matrix((self.nnodes, self.nnodes))

        # Form a KDTree
        tree = KDTree(X)
        result = tree.query_ball_tree(tree, r0)

        for i, rlist in enumerate(result):
            w = []
            wvars = []
            for j in rlist:
                r = np.sqrt(np.dot(X[i,:] - X[j,:], X[i,:] - X[j,:]))
                if r < r0:
                    w.append((r0 - r)/r0)
                    wvars.append(j)

            # Normalize the weights
            w = np.array(w)
            w /= np.sum(w)

            # Set the weights into the filter matrix W
            F[i, wvars] = w

        # Covert the matrix to a CSR data format
        self.F = F.tocsr()

        return

    def mass(self, x):
        """
        Compute the mass of the structure
        """

        mass = plane_stress.computemass(self.conn.T, self.X.T, x)

        return mass

    def mass_grad(self, x):
        """
        Compute the derivative of the mass
        """
        dmdx = np.zeros(x.shape)
        plane_stress.computemassderiv(self.conn.T, self.X.T, dmdx)

        return dmdx

    def compliance(self, x):
        """
        Compute the structural compliance
        """

        # Compute the filtered compliance. Note that 'dot' is scipy
        # matrix-vector multiplicataion
        rho = self.F.dot(x)

        # Compute the stiffness matrix
        plane_stress.computekmat(self.conn.T, self.vars.T, self.X.T,
            self.qval, self.C.T, rho, self.rowp, self.cols, self.Kvals)

        # Form the matrix
        Kmat = sparse.csr_matrix((self.Kvals, self.cols, self.rowp),
                                 shape=(self.nvars, self.nvars))
        self.Kmat = Kmat.tocsc()
        self.LU = linalg.dsolve.factorized(self.Kmat)

        # Compute the solution to the linear system K*u = f
        self.u = self.LU(self.force)

        # Return the compliance
        return np.dot(self.force, self.u)

    def compliance_grad(self, x):
        """
        Compute the gradient of the compliance using the adjoint
        method.

        Since the governing equations are self-adjoint, and the
        function itself takes a special form:

        K*psi = f => psi = u

        So we can skip the adjoint computation itself since we have
        the displacement vector u from the solution.

        d(compliance)/dx = - u^{T}*d(K*u - f)/dx = - u^{T}*dK/dx*u
        """

        # Compute the filtered variables
        rho = self.F.dot(x)

        # First compute the derivative with respect to the filtered
        # variables
        dKdrho = np.zeros(x.shape)

        plane_stress.computekmatderiv(self.conn.T, self.vars.T, self.X.T,
            self.qval, self.C.T, rho, self.u, self.u, dKdrho)

        # Now evaluate the effect of the filter
        dcdx = -(self.F.transpose()).dot(dKdrho)

        return dcdx

    def getVarsAndBounds(self, x, lb, ub):
        """Get the variable values and bounds"""
        lb[:] = 1e-3
        ub[:] = 1.0
        x[:] = 0.95
        return

    def evalObjCon(self, x):
        """
        Return the objective, constraint and fail flag
        """

        fail = 0
        obj = self.compliance(x[:])
        con = np.array([0.4*self.total_mass - self.mass(x[:])])

        return fail, obj, con

    def evalObjConGradient(self, x, g, A):
        """
        Return the objective, constraint and fail flag
        """

        fail = 0
        g[:] = self.compliance_grad(x[:])
        A[0][:] = -self.mass_grad(x[:])

        return fail